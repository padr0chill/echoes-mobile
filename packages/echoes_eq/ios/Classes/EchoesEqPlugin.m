#import "EchoesEqPlugin.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaToolbox/MediaToolbox.h>
#import <objc/runtime.h>
#include <math.h>
#include <string.h>

// ─── Эквалайзер ECHOES ───────────────────────────────────────────────────────────────────────────────
// 10 полос (peaking EQ, формулы RBJ «Audio EQ Cookbook», Q ≈ 1.41 — октава) + предусиление и мягкий
// предел от перегруза. Настройки — глобальные: меняются из Dart (канал «echoes/eq») и подхватываются
// звуковым потоком на следующем буфере — без перезапуска трека.
//
// Как звук попадает сюда: just_audio играет через AVQueuePlayer; мы подменяем его
// insertItem:afterItem: (и AVPlayer.replaceCurrentItemWithPlayerItem:) и каждому новому элементу вешаем
// на звуковую дорожку MTAudioProcessingTap. Для HLS-потоков iOS такие «краны» не поддерживает — там
// звук идёт без эквалайзера (дорожек у такого элемента нет, мы просто ничего не делаем).

#define EQ_BANDS 10
#define EQ_MAX_CH 8

static const double kFreqs[EQ_BANDS] = {32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000};
static volatile float gGains[EQ_BANDS];
static volatile float gPreamp = 0;
static volatile int gEnabled = 0;
static volatile int gVersion = 1;

typedef struct {
  double b0, b1, b2, a1, a2;
} EqCoef;

typedef struct {
  EqCoef coef[EQ_BANDS];
  int skip[EQ_BANDS];
  double z1[EQ_BANDS][EQ_MAX_CH];
  double z2[EQ_BANDS][EQ_MAX_CH];
  double sampleRate;
  double gain;
  int nonInterleaved;
  int isFloat;
  int version;
} EqState;

static void EqCompute(EqState *s) {
  for (int b = 0; b < EQ_BANDS; b++) {
    double g = gGains[b];
    double f = kFreqs[b];
    if (fabs(g) < 0.05 || f >= s->sampleRate * 0.45) {
      s->skip[b] = 1;
      continue;
    }
    s->skip[b] = 0;
    double A = pow(10.0, g / 40.0);
    double w0 = 2.0 * M_PI * f / s->sampleRate;
    double alpha = sin(w0) / (2.0 * 1.41);
    double cw = cos(w0);
    double a0 = 1.0 + alpha / A;
    s->coef[b].b0 = (1.0 + alpha * A) / a0;
    s->coef[b].b1 = (-2.0 * cw) / a0;
    s->coef[b].b2 = (1.0 - alpha * A) / a0;
    s->coef[b].a1 = (-2.0 * cw) / a0;
    s->coef[b].a2 = (1.0 - alpha / A) / a0;
  }
  s->gain = pow(10.0, gPreamp / 20.0);
  s->version = gVersion;
}

// мягкий предел: до 0.9 — как есть, выше — плавно к 1.0 (без жёсткого «хруста» клиппинга)
static inline double EqSoftClip(double x) {
  double a = fabs(x);
  if (a <= 0.9) return x;
  double y = 0.9 + 0.1 * tanh((a - 0.9) / 0.1);
  return x < 0 ? -y : y;
}

static void EqTapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
  EqState *s = (EqState *)calloc(1, sizeof(EqState));
  *tapStorageOut = s;
}

static void EqTapFinalize(MTAudioProcessingTapRef tap) {
  void *s = MTAudioProcessingTapGetStorage(tap);
  if (s) free(s);
}

static void EqTapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames,
                         const AudioStreamBasicDescription *fmt) {
  EqState *s = (EqState *)MTAudioProcessingTapGetStorage(tap);
  if (!s) return;
  s->sampleRate = fmt->mSampleRate > 0 ? fmt->mSampleRate : 44100.0;
  s->nonInterleaved = (fmt->mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
  s->isFloat = (fmt->mFormatFlags & kAudioFormatFlagIsFloat) != 0 && fmt->mBitsPerChannel == 32;
  memset(s->z1, 0, sizeof(s->z1));
  memset(s->z2, 0, sizeof(s->z2));
  s->version = 0;
}

static void EqTapUnprepare(MTAudioProcessingTapRef tap) {}

static void EqTapProcess(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags,
                         AudioBufferList *bufferListInOut, CMItemCount *numberFramesOut,
                         MTAudioProcessingTapFlags *flagsOut) {
  OSStatus err = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, NULL,
                                                    numberFramesOut);
  if (err != noErr) return;
  EqState *s = (EqState *)MTAudioProcessingTapGetStorage(tap);
  if (!s || !gEnabled || !s->isFloat) return;
  if (s->version != gVersion) EqCompute(s);
  CMItemCount n = *numberFramesOut;
  for (UInt32 bi = 0; bi < bufferListInOut->mNumberBuffers; bi++) {
    AudioBuffer *buf = &bufferListInOut->mBuffers[bi];
    float *data = (float *)buf->mData;
    if (!data) continue;
    int chInBuf = s->nonInterleaved ? 1 : (int)buf->mNumberChannels;
    if (chInBuf < 1) chInBuf = 1;
    for (int c = 0; c < chInBuf; c++) {
      int ch = s->nonInterleaved ? (int)bi : c;
      if (ch >= EQ_MAX_CH) continue;
      for (CMItemCount i = 0; i < n; i++) {
        float *p = data + i * chInBuf + c;
        double x = (double)(*p) * s->gain;
        for (int b = 0; b < EQ_BANDS; b++) {
          if (s->skip[b]) continue;
          EqCoef *k = &s->coef[b];
          double y = k->b0 * x + s->z1[b][ch];
          s->z1[b][ch] = k->b1 * x - k->a1 * y + s->z2[b][ch];
          s->z2[b][ch] = k->b2 * x - k->a2 * y;
          x = y;
        }
        *p = (float)EqSoftClip(x);
      }
    }
  }
}

static void EchoesAttachEq(AVPlayerItem *item) {
  if (item == nil || item.audioMix != nil) return;
  AVAsset *asset = item.asset;
  if (asset == nil) return;
  [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ]
                       completionHandler:^{
                         NSError *e = nil;
                         if ([asset statusOfValueForKey:@"tracks" error:&e] != AVKeyValueStatusLoaded) return;
                         NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
                         if (tracks.count == 0) return;  // HLS и т. п. — без эквалайзера
                         dispatch_async(dispatch_get_main_queue(), ^{
                           if (item.audioMix != nil) return;
                           MTAudioProcessingTapCallbacks cb;
                           cb.version = kMTAudioProcessingTapCallbacksVersion_0;
                           cb.clientInfo = NULL;
                           cb.init = EqTapInit;
                           cb.finalize = EqTapFinalize;
                           cb.prepare = EqTapPrepare;
                           cb.unprepare = EqTapUnprepare;
                           cb.process = EqTapProcess;
                           MTAudioProcessingTapRef tap = NULL;
                           OSStatus st = MTAudioProcessingTapCreate(kCFAllocatorDefault, &cb,
                                                                    kMTAudioProcessingTapCreationFlag_PostEffects,
                                                                    &tap);
                           if (st != noErr || tap == NULL) return;
                           AVMutableAudioMixInputParameters *params =
                               [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:tracks.firstObject];
                           params.audioTapProcessor = tap;
                           CFRelease(tap);
                           AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
                           mix.inputParameters = @[ params ];
                           item.audioMix = mix;
                         });
                       }];
}

// ─── перехват постановки элементов в очередь плеера ───
static IMP gOrigInsert = NULL;
static IMP gOrigReplace = NULL;

static void EqInsertItem(id self, SEL _cmd, AVPlayerItem *item, AVPlayerItem *after) {
  EchoesAttachEq(item);
  ((void (*)(id, SEL, AVPlayerItem *, AVPlayerItem *))gOrigInsert)(self, _cmd, item, after);
}

static void EqReplaceItem(id self, SEL _cmd, AVPlayerItem *item) {
  EchoesAttachEq(item);
  ((void (*)(id, SEL, AVPlayerItem *))gOrigReplace)(self, _cmd, item);
}

static void EchoesSwizzle(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    Method m1 = class_getInstanceMethod([AVQueuePlayer class], @selector(insertItem:afterItem:));
    if (m1) gOrigInsert = method_setImplementation(m1, (IMP)EqInsertItem);
    Method m2 = class_getInstanceMethod([AVPlayer class], @selector(replaceCurrentItemWithPlayerItem:));
    if (m2) gOrigReplace = method_setImplementation(m2, (IMP)EqReplaceItem);
  });
}

@implementation EchoesEqPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  for (int i = 0; i < EQ_BANDS; i++) gGains[i] = 0;
  EchoesSwizzle();
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"echoes/eq"
                                                              binaryMessenger:[registrar messenger]];
  EchoesEqPlugin *instance = [[EchoesEqPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"set"]) {
    NSDictionary *args = call.arguments;
    NSArray *gains = args[@"gains"];
    for (int i = 0; i < EQ_BANDS; i++) {
      double v = (i < (int)gains.count) ? [gains[i] doubleValue] : 0.0;
      if (v > 12) v = 12;
      if (v < -12) v = -12;
      gGains[i] = (float)v;
    }
    gPreamp = (float)[args[@"preamp"] doubleValue];
    gEnabled = [args[@"enabled"] boolValue] ? 1 : 0;
    gVersion = gVersion + 1;
    result(nil);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

@end
