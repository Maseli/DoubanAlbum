//
//  DAHomeViewController.h
//  DoubanAlbum
//
//  Created by Tonny on 12-12-8.
//  Copyright (c) 2012年 SlowsLab. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DAHomeViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UICollectionViewDataSource, UICollectionViewDelegate, UIAlertViewDelegate>{
    NSDictionary            *_appData;
    
    NSDictionary            *_dataSource;
    NSUInteger              _seletedCategory;
    
    __weak IBOutlet UITableView *_tableView;
    __weak IBOutlet UICollectionView *_collectionView;
    
    // Navigationbar的刷新按钮
    UIButton                *_refreshBtn;

    NSUInteger              _lastSelectedRow;
}


/* 有些方法没在interface里声明,说明是一个外部不能调用的内部方法 */

- (void)checkCagetory:(UIButton *)button;

@end
