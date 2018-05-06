//
//  ViewController.m
//  AduioUnitDemo
//
//  Created by SUNYAZHOU on 2018/5/5.
//  Copyright © 2018年 sunyazhou. All rights reserved.
//

#import "ViewController.h"
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>

static const NSUInteger bufferCount      = 3;        //缓冲区数量
static const UInt32     inBufferByteSize = 2048;     //缓冲的大小字节
//Objective - C 实现部分
@interface ViewController () {
    AudioComponent              _audioComponent;
    AudioComponentInstance      _audioUnit;
    AudioStreamBasicDescription _asbd;
    AudioQueueRef               _audioQueue;           //播放音频队列
    AudioQueueBufferRef         _audioQueueBuffers[bufferCount]; //音频缓存
}

@property(nonatomic, assign) int index;

@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self configSession];
}

- (void)configSession {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    //添加通知
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeAudioRoute:) name:AVAudioSessionRouteChangeNotification object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    
    //创建AudioUnit
    AudioComponentDescription acd = {0};
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_RemoteIO;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    _audioComponent = AudioComponentFindNext(NULL, &acd);
    
    OSStatus status = noErr;
    status = AudioComponentInstanceNew(_audioComponent, &_audioUnit);
    CheckStatus(status, @"create failed ", YES);
    
    //设置参数属性
    UInt32 flagOne = 1;
    AudioUnitSetProperty(_audioUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         1,
                         &flagOne,
                         sizeof(flagOne));
    
    AudioStreamBasicDescription asbd ={0};
    asbd.mSampleRate = 44100;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
    asbd.mChannelsPerFrame = 1;
    asbd.mFramesPerPacket = 1;
    asbd.mBitsPerChannel = 16;
    asbd.mBytesPerFrame = asbd.mBitsPerChannel * asbd.mChannelsPerFrame / 8 ;
    asbd.mBytesPerPacket = asbd.mFramesPerPacket * asbd.mBytesPerFrame;
    asbd.mReserved = 0;
    
    //设置格式
    AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd, sizeof(asbd));
    
    //AudioUnit的回掉函数 类似我们的delegate
    AURenderCallbackStruct cb = {0};
    cb.inputProcRefCon = (__bridge void * _Nullable)(self);
    cb.inputProc = handleInputBuffer;
    
    //设置录制回调
    AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, sizeof(cb));
    
    //初始化
    status = AudioUnitInitialize(_audioUnit);
    CheckStatus(status, @"初始化AudioUnit 失败", YES);
    
    //启动AudioUnit Output
    AudioOutputUnitStart(_audioUnit);
    
    
    //使用AudioQueue播放
    _asbd.mSampleRate = 44100;
    _asbd.mFormatID = kAudioFormatLinearPCM;
    _asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    _asbd.mChannelsPerFrame = 1;
    _asbd.mFramesPerPacket = 1;
    _asbd.mBitsPerChannel = 16;
    _asbd.mBytesPerFrame = asbd.mBytesPerFrame;
    _asbd.mBytesPerPacket = asbd.mBytesPerPacket;
    //Creates a new playback audio queue object.
    AudioQueueNewOutput(&_asbd, BufferCallback, (__bridge void * _Nullable)(self), nil, nil, 0, &_audioQueue);
    
    
    //初始化音频缓冲区
    for (int i = 0; i < bufferCount; i++) {
        //创建buffer
        status = AudioQueueAllocateBuffer(_audioQueue, inBufferByteSize, &_audioQueueBuffers[i]);
        CheckStatus(status, @"creat AudioQueue fail", YES);
        //初始化
        memset(_audioQueueBuffers[i]->mAudioData, 0, inBufferByteSize);
    }
    //设置AudioQueue
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, 0.5);
}

//C 函数实现部分
static OSStatus handleInputBuffer(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData)
{
    ViewController *vc = (__bridge ViewController *)(inRefCon);
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = NULL;
    bufferList.mBuffers[0].mDataByteSize = 0;
    AudioUnitRender(vc->_audioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, &bufferList);
    //SInt16 *rece = (SInt16 *)bufferList.mBuffers[0].mData;
    void *data = malloc(bufferList.mBuffers[0].mDataByteSize);
    memcpy(data, bufferList.mBuffers[0].mData, bufferList.mBuffers[0].mDataByteSize);
    //play
    AudioQueueBufferRef audioBuffer = NULL;
    if (vc->_index == 2) {
        vc->_index = 0;
    }
    
    audioBuffer = vc->_audioQueueBuffers[vc->_index];
    vc->_index ++;
    audioBuffer->mAudioDataByteSize = bufferList.mBuffers[0].mDataByteSize;
    memset(audioBuffer->mAudioData, 0, bufferList.mBuffers[0].mDataByteSize);
    memcpy(audioBuffer->mAudioData, data, bufferList.mBuffers[0].mDataByteSize);
    
    AudioQueueEnqueueBuffer(vc->_audioQueue, audioBuffer, 0, NULL);
    free(data);
    return noErr;
}

//AudioQueue回调
static void BufferCallback(void *inUserData, AudioQueueRef inAQ,
                           AudioQueueBufferRef buffer){
    NSLog(@"BufferCallback is working");
//    ViewController *vc = (__bridge ViewController *)(inUserData);
}

//check func
static void CheckStatus(OSStatus status, NSString *message, BOOL fatal) {
    if (status != noErr) {
        char fourCC[16];
        *(UInt32 *)fourCC = CFSwapInt32HostToBig(status);
        fourCC[4] = '\0';
        if (isprint(fourCC[0]) && isprint(fourCC[1]) &&
            isprint(fourCC[2]) && isprint(fourCC[4])) {
            NSLog(@"%@:%s",message, fourCC);
        } else {
            NSLog(@"%@:%d",message, (int)status);
        }
        
        if (fatal) {
            exit(-1);
        }
    }
}


//音频线路发生变化
- (void)changeAudioRoute:(NSNotification *)noti{
    if ([noti.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue] ==
        AVAudioSessionRouteChangeReasonOldDeviceUnavailable) { //拔出耳塞
        AudioOutputUnitStop(_audioUnit);
        
    }else  if ([noti.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue] ==
               AVAudioSessionRouteChangeReasonNewDeviceAvailable){
        for (AVAudioSessionPortDescription* desc in [[AVAudioSession sharedInstance].currentRoute outputs]) {
            if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
                return;
        }
        AudioOutputUnitStop(_audioUnit);
    }
}

//处理中途打断
- (void)handleInterruption:(NSNotification *)notification{
    
}
- (IBAction)onEnableButtonClick:(UIButton *)sender {
    sender.selected = !sender.selected;
    if (sender.selected) {
        AudioQueueStart(_audioQueue, NULL);
    }else{
        AudioQueueStop(_audioQueue, YES);
    }
}

- (IBAction)volumnChange:(UISlider *)sender {
    //设置AudioQueue
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, sender.value);
}


@end



