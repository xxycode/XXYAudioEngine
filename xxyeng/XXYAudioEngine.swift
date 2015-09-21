//
//  XXYAudioEngine.swift
//  xxyeng
//
//  Created by Xiaoxueyuan on 15/9/18.
//  Copyright (c) 2015年 Xiaoxueyuan. All rights reserved.
//

import UIKit
import AVFoundation

@objc protocol XXYAudioEngineDelegate:NSObjectProtocol{
    //文件下载进度
    optional func audioFileDownloadProgress(engine:XXYAudioEngine,progress:CGFloat)
    //文件播放进度
    optional func audioPlayProgress(engine:XXYAudioEngine,progress:CGFloat)
    //开始播放
    optional func audioDidBeginPlay(engine:XXYAudioEngine)
    //播放状态改变
    optional func audioPlayStateDidChanged(engine:XXYAudioEngine)
}

enum XXYAudioEnginePlayState{
    case None
    case Playing
    case Stopped
    case Paused
    case Ended
    case Error
}

class XXYAudioEngine: NSObject,NSURLSessionDataDelegate,AVAudioPlayerDelegate {
    var player:AVAudioPlayer?
    var url:NSURL?
    var sizeBuffer = Int64(100000)
    var duration = NSTimeInterval(0)
    var currentTime = NSTimeInterval(0)
    weak var delegate:XXYAudioEngineDelegate?
    var playerState = XXYAudioEnginePlayState.None{
        didSet{
            delegate?.audioPlayStateDidChanged?(self)
        }
    }
    private var saveCacheToFile = false
    private var cacheFileName = ""
    private var filePath = ""
    private var isPlayed = false
    static var folderName = "com.xxycode.xxyaudioengine"
    static var cacheFilePath:String{
        get{
            var cacheDir = (NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask).last as! NSURL).path
            return cacheDir!.stringByAppendingPathComponent(XXYAudioEngine.folderName)
        }
    }
    private var outputStream:NSOutputStream?
    private var response:NSURLResponse?
    private var totalLength = Int64(0)
    private var totalLengthReadForFile = Int64(0)
    private var fileFullPath = ""
    private var error:NSError?
    private var timer:NSTimer?
    private var timerInterval = NSTimeInterval(0.1)
    private var downloadTask:NSURLSessionDataTask?
    init(url:String,playInBackground:Bool,saveCache:Bool,cacheName:String?){
        super.init()
        self.url = NSURL(string: url)
        if playInBackground {
            configBackground()
        }
        if cacheName == nil || (cacheName! as NSString).stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()) == ""{
            let time = NSDate()
            let timeStamp = "\(Int(time.timeIntervalSince1970))"
            let tdata = timeStamp.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: true)
            cacheFileName = tdata!.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
        }else{
            cacheFileName = cacheName!
        }
        var cacheDir = (NSFileManager.defaultManager().URLsForDirectory(.CachesDirectory, inDomains: .UserDomainMask).last as! NSURL).path
        filePath = cacheDir!.stringByAppendingPathComponent(XXYAudioEngine.folderName)
        if NSFileManager().createDirectoryAtPath(filePath, withIntermediateDirectories: true, attributes: nil, error: nil) == false{
            println("创建缓存文件夹失败")
        }
        saveCacheToFile = saveCache
    }
    
    
    private func configBackground(){
        AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, error: nil)
        AVAudioSession.sharedInstance().setActive(true, error: nil)
        UIApplication.sharedApplication().beginReceivingRemoteControlEvents()
    }
    
    private func playFile(){
        var path = fileFullPath
        var err:NSError?
        if player == nil{
            player = AVAudioPlayer(contentsOfURL: NSURL(string: path), error: &err)
            player?.meteringEnabled = true
            if err != nil{
                error = err
                playerState = .Error
                println("初始化播放器失败\(err?.description)")
            }
        }
        if player != nil{
            player?.prepareToPlay()
            player?.play()
            player?.delegate = self
            duration = player!.duration
            startTimer()
            playerState = .Playing
        }
    }
    
    private func startTimer(){
        if timer != nil{
            timer?.invalidate()
            timer = nil
        }
        timer = NSTimer(timeInterval: timerInterval, target: self, selector: "playerTimerAction", userInfo: nil, repeats: true)
        NSRunLoop.currentRunLoop().addTimer(timer!, forMode: NSRunLoopCommonModes)
        timer?.fire()
    }
    
    @objc private func playerTimerAction(){
        currentTime = player!.currentTime
        delegate?.audioPlayProgress?(self, progress: CGFloat(currentTime/duration))
        if player?.playing == false{
            playerState = .Paused
        }else{
            playerState = .Playing
        }
        if duration - currentTime <= 0.05{
            if saveCacheToFile == false{
                if NSFileManager.defaultManager().fileExistsAtPath(fileFullPath) == true{
                    NSFileManager.defaultManager().removeItemAtPath(fileFullPath, error: nil)
                }
            }
            playerState = .Ended
            timer?.invalidate()
            timer = nil
        }
    }
    //MARK: - PublicMethod
    //开始播放
    func play(){
        var session:NSURLSession?
        if (UIDevice.currentDevice().systemVersion as NSString).floatValue >= 8.0{
            session = NSURLSession(configuration: NSURLSessionConfiguration.backgroundSessionConfigurationWithIdentifier(XXYAudioEngine.folderName), delegate: self,
                delegateQueue: NSOperationQueue())
        }else{
            session = NSURLSession(configuration: NSURLSessionConfiguration.backgroundSessionConfiguration(XXYAudioEngine.folderName), delegate: self,
                delegateQueue: NSOperationQueue())
        }
        
        let request = NSURLRequest(URL: url!, cachePolicy: .UseProtocolCachePolicy, timeoutInterval: 15)
        if downloadTask != nil{
            downloadTask?.cancel()
            stop()
            downloadTask = nil
        }
        downloadTask = session!.dataTaskWithRequest(request)
        downloadTask?.resume()
    }
    //根据URL播放
    func play(aUrl:String){
        url = NSURL(string: aUrl)
        play()
    }
    //暂停
    func pause(){
        if player?.playing == true {
            playerState = .Paused
            player?.pause()
            timer?.invalidate()
        }
    }
    //继续
    func resume(){
        if player?.playing == false {
            playerState = .Playing
            player?.play()
            startTimer()
        }
    }
    //停止
    func stop(){
        playerState = .Stopped
        downloadTask?.cancel()
        timer?.invalidate()
    }
    //获取音频当前的平均分贝大小(-120 ~ 0),可用于绘制波形图
    func currentAveragePower() -> Float{
        if player != nil{
            player!.updateMeters()
            return (player!.averagePowerForChannel(0) + player!.averagePowerForChannel(1))/2
        }
        return 0
    }
    //获取音频当前的最大分贝大小(-160 ~ 0)
    func currentPeakPower() -> Float{
        if player != nil{
            player!.updateMeters()
            return (player!.peakPowerForChannel(0) + player!.peakPowerForChannel(1))/2
        }
        return 0
    }
    //MARK: - 类方法
    //清除全部缓存
    class func cleanAllCacheFile(){
        let manager = NSFileManager.defaultManager()
        let cacheItems = XXYAudioEngine.cachesList()
        if cacheItems == nil {
            return
        }
        for item in cacheItems!{
            let fullPath = XXYAudioEngine.cacheFilePath.stringByAppendingPathComponent(item)
            if manager.fileExistsAtPath(fullPath){
                manager.removeItemAtPath(fullPath, error: nil)
            }
        }
    }
    //清除指定缓存(需加上后缀名，如: 123.mp3)
    class func cleanCacheFileWithCacheKey(cacheKey:String){
        let fullPath = XXYAudioEngine.cacheFilePath.stringByAppendingPathComponent(cacheKey)
        let manager = NSFileManager.defaultManager()
        if manager.fileExistsAtPath(fullPath){
            manager.removeItemAtPath(fullPath, error: nil)
        }
    }
    //获取缓存文件列表(相对路径，如:[123.mp3,234.mp3])
    class func cachesList() -> Array<String>?{
        let manager = NSFileManager.defaultManager()
        let cacheItems = manager.contentsOfDirectoryAtPath(XXYAudioEngine.cacheFilePath, error: nil)
        if cacheItems == nil {
            return nil
        }
        return cacheItems as? Array<String>
    }
    //获取缓存文件完整目录列表
    class func cacheFileFullPathes() -> Array<String>{
        var res = Array<String>()
        var arr = XXYAudioEngine.cachesList()
        if arr != nil{
            for item in arr!{
                res.append(XXYAudioEngine.cacheFilePath.stringByAppendingPathComponent(item))
            }
        }
        return res
    }
    //获取缓存大小(单位：MB)
    class func cacheSize() -> Float{
        var fileList = XXYAudioEngine.cacheFileFullPathes()
        var totalSize = UInt64(0)
        for item in fileList{
            let attr:NSDictionary = NSFileManager.defaultManager().attributesOfItemAtPath(item, error: nil)!
            totalSize += attr.fileSize()
        }
        return Float(totalSize)/(1024*1024)
    }
    //获取各个缓存文件的下载完成时间
    class func cacheFinishedDownLoadDates() -> Array<NSDate>{
        var fileList = XXYAudioEngine.cacheFileFullPathes()
        var res = Array<NSDate>()
        for item in fileList{
            let attr:NSDictionary = NSFileManager.defaultManager().attributesOfItemAtPath(item, error: nil)!
            if attr.fileModificationDate() != nil{
                res.append(attr.fileModificationDate()!)
            }else{
                res.append(NSDate())
            }
        }
        return res
    }
    
    //MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(player: AVAudioPlayer!, successfully flag: Bool) {
        delegate?.audioPlayProgress?(self, progress: 1)
        playerState = .Ended
    }
    //MARK: - URLSessionDelegate
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveResponse response: NSURLResponse, completionHandler: (NSURLSessionResponseDisposition) -> Void) {
        completionHandler(.Allow)
        self.response = response
        totalLength = response.expectedContentLength
        var suggestedFilename = response.suggestedFilename
        var fileSuffix = "." + response.suggestedFilename!.componentsSeparatedByString(".").last!
        fileFullPath = filePath.stringByAppendingPathComponent(cacheFileName) + fileSuffix
        println("文件保存路径：\(fileFullPath)")
        if NSFileManager.defaultManager().fileExistsAtPath(fileFullPath) == true{
            NSFileManager.defaultManager().removeItemAtPath(fileFullPath, error: nil)
        }
        outputStream = NSOutputStream(toFileAtPath: fileFullPath, append: true)
        outputStream?.open()
        playerState = .Playing
    }
    
    func URLSession(session: NSURLSession, dataTask: NSURLSessionDataTask, didReceiveData data: NSData) {
        var length = data.length
        while(true){
            var totalWritten = 0
            if outputStream?.hasSpaceAvailable == true{
                var dataBuffer = UnsafePointer<UInt8>(data.bytes)
                var numberOfWritten = 0
                while(totalWritten < length){
                    numberOfWritten = outputStream!.write(dataBuffer, maxLength: length)
                    if numberOfWritten == -1{
                        break;
                    }
                    totalWritten += numberOfWritten
                }
                totalLengthReadForFile += length
                delegate?.audioFileDownloadProgress?(self, progress: CGFloat(totalLengthReadForFile)/CGFloat(totalLength))
                if totalLengthReadForFile > sizeBuffer && playerState == .Playing{
                    if isPlayed == false{
                        delegate?.audioDidBeginPlay?(self)
                        isPlayed = true
                    }
                    playFile()
                }
                break;
            }
        }
    }
}
