//
//  ViewController.swift
//  xxyeng
//
//  Created by Xiaoxueyuan on 15/9/18.
//  Copyright (c) 2015年 Xiaoxueyuan. All rights reserved.
//

import UIKit

class ViewController: UIViewController,XXYAudioEngineDelegate {
    @IBOutlet weak var urlBOX: UITextField!
    //http://radio.sky31.com/uploads/audio/2015/09/15/4C0IW.mp3
    var shapeLayer = CAShapeLayer()
    var eng:XXYAudioEngine?
    override func viewDidLoad() {
        super.viewDidLoad()
        
        eng = XXYAudioEngine(url: "http://120.25.57.2:234//11.mp3", playInBackground: true, saveCache: true, cacheName: nil)
        eng!.delegate = self
        shapeLayer.frame = CGRectMake(20, 120, 40, 100)
        view.layer.addSublayer(shapeLayer)
        shapeLayer.fillColor = UIColor.redColor().CGColor
        
        //eng!.play()
        
    }
    func drawShape(){
        var power = -CGFloat(eng!.currentAveragePower())
        if power > 30{
            power = 30
        }
        var progress = power/30
        var origy = progress * 120
        let path = UIBezierPath()
        path.moveToPoint(CGPointMake(0, origy))
        path.addLineToPoint(CGPointMake(40, origy))
        path.addLineToPoint(CGPointMake(40, 120))
        path.addLineToPoint(CGPointMake(0, 120))
        path.addLineToPoint(CGPointMake(0, origy))
        shapeLayer.path = path.CGPath

    }
    @IBAction func playAction(sender: AnyObject) {
        eng?.play(urlBOX.text)
    }
    @IBAction func pauseAction(sender: AnyObject) {
        var btn = sender as! UIButton
        if eng?.playerState == .Playing{
            eng?.pause()
            btn.setTitle("继续", forState: .Normal)
        }else{
            eng?.resume()
            btn.setTitle("暂停", forState: .Normal)
        }
    }
    @IBAction func clean(sender: AnyObject) {
        println("清除了\(XXYAudioEngine.cacheSize())M缓存")
        XXYAudioEngine.cleanAllCacheFile()
    }
    
    func audioDidBeginPlay(engine: XXYAudioEngine) {
        println("开始了")
        let displayLink = CADisplayLink(target: self, selector: "drawShape")
        displayLink.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        displayLink.paused = false
    }

    @IBAction func tAct(sender: UIButton) {
    }

}

