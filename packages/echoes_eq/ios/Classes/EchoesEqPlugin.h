#import <Flutter/Flutter.h>

/// Эквалайзер ECHOES: перехватывает элементы, которые плеер (just_audio → AVQueuePlayer) ставит в
/// очередь, и вешает на их звуковую дорожку MTAudioProcessingTap с 10 полосовыми фильтрами.
@interface EchoesEqPlugin : NSObject <FlutterPlugin>
@end