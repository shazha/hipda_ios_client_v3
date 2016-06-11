//
//  HPThreadViewController.m
//  HiPDA
//
//  Created by wujichao on 13-11-11.
//  Copyright (c) 2013年 wujichao. All rights reserved.
//

#import "HPHttpClient.h"
#import "HPThread.h"
#import "HPUser.h"
#import "HPCache.h"
#import "HPMessage.h"
#import "HPNewPost.h"
#import "HPAccount.h"
#import "HPDatabase.h"
#import "HPTheme.h"
#import "HPSetting.h"

#import "HPThreadViewController.h"
#import "HPThreadCell.h"
#import "HPReadViewController.h"
#import "SWRevealViewController.h"
#import "EGORefreshTableFooterView.h"
#import "HPLoginViewController.h"
#import "HPRearViewController.h"
#import "HPNewThreadViewController.h"
#import "HPUserViewController.h"
#import "HPDebugCrawlerViewController.h"

#import <SVProgressHUD.h>
#import <ZAActivityBar/ZAActivityBar.h>
#import "UIAlertView+Blocks.h"
#import <UIImageView+WebCache.h>
#import "UIBarButtonItem+ImageItem.h"
#import "EGORefreshTableFooterView.h"
#import "BBBadgeBarButtonItem.h"
#import "HPIndecator.h"
#import "NSString+Additions.h"
#import "HPNavigationDropdownMenu.h"
#import "HPThreadFilterMenu.h"
#import <ReactiveCocoa.h>

typedef enum{
	PullToRefresh = 0,
	ClickToRefresh,
	LoadMore
} LoadType;


@interface HPThreadViewController () <MCSwipeTableViewCellDelegate, UIAlertViewDelegate, HPCompositionDoneDelegate, HPThreadCellDelegate>

@property (nonatomic, strong) NSMutableArray *threads;
@property (nonatomic, assign) NSInteger current_fid;
@property (nonatomic, assign) NSInteger current_page;

@property (nonatomic, strong) UIBarButtonItem *refreshButtonBI;
@property (nonatomic, strong) UIBarButtonItem *refreshIndicatorBI;
@property (nonatomic, strong) UIActivityIndicatorView *refreshIndicator;
@property (nonatomic, strong) UIBarButtonItem *composeBI;

@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, strong) EGORefreshTableFooterView *loadingMoreView;

@property (nonatomic, strong) NSDate *lastEnterBackgroundDate;

@property (nonatomic, assign) NSInteger currentFontSize;

@property (nonatomic, strong) HPNavigationDropdownMenu *dropMenu;
@property (nonatomic, strong) HPThreadFilterMenu *filterMenu;

@end

@implementation HPThreadViewController {
    ;
}


- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        ;
    }
    return self;
}

- (id)initDefaultForum:(NSInteger)fid title:(NSString *)title
{
    self = [super init];
    if (self) {
        [Flurry logEvent:@"ThreadVC LoadForum" withParameters:@{@"fid":@(fid),@"title":title}];
        _current_page = 1;
        _current_fid = fid;
        self.title = title;
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //
    [self setActionButton];
    
    self.tableView.rowHeight = 70.0f;
    [self.tableView setBackgroundColor:[HPTheme backgroundColor]];
    [self.tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
    
    //
    [self.tableView addObserver:self forKeyPath:@"contentOffset" options:NSKeyValueObservingOptionNew context:(__bridge void *)(self)];
    
    //
    self.refreshControl = [[UIRefreshControl alloc] init];
    [self.refreshControl addTarget:self
                            action:@selector(refresh:)
                  forControlEvents:UIControlEventValueChanged];
    self.refreshControl.backgroundColor = [UIColor clearColor];
    
    HPThreadFilterMenu *filterMenu = [[HPThreadFilterMenu alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 230)];//暂时写死高度, 折腾了一下autolayout自动算, 但是要求filterMenu的superview使用autolayout布局filterview
    HPNavigationDropdownMenu *menuView = [[HPNavigationDropdownMenu alloc] initWithTitle:self.title
                                                                              customView:filterMenu
                                                                           containerView:self.view];
    self.dropMenu = menuView;
    self.filterMenu = filterMenu;
    
    self.navigationItem.titleView = menuView;
    
    @weakify(self);
    [RACObserve(filterMenu, currentFilter) subscribeNext:^(NSDictionary *filter) {
        @strongify(self);
        if ([filter[@"filter"] isEqualToString:@""] &&
            [filter[@"orderby"] isEqualToString:@"lastpost"]) {
            [self.dropMenu setMenuTitleText:self.title];
        } else {
            [self.dropMenu setMenuTitleText:[self.title stringByAppendingString:@"*"]];
        }
    }];
    filterMenu.submitBlock = ^{
        @strongify(self);
        [self.dropMenu dismiss];
        [self refresh:[UIButton new]];
    };
    [filterMenu updateWithFid:self.current_fid];
    
    // 用户改变了参数, 但是不点击确定就关掉了面板, 就重置页面
    [RACObserve(menuView, isShown) subscribeNext:^(NSNumber *value) {
        @strongify(self);
        if ([value boolValue] == NO) {
            [self.filterMenu updateWithFid:self.current_fid];
        }
    }];
    
    
    //
    [self refresh:[UIButton new]];
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    SWRevealViewController *revealController = [self revealViewController];
    [self.navigationController.view addGestureRecognizer:revealController.panGestureRecognizer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActiveNotification:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(UIApplicationDidEnterBackgroundNotification:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:[UIApplication sharedApplication]];
    
    if (_currentFontSize &&
        _currentFontSize != [Setting integerForKey:HPSettingFontSizeAdjust]) {
        [self.tableView reloadData];
        //NSLog(@"_currentFontSize && _currentFontSize != SETTING");
    } else {
        _currentFontSize = [Setting integerForKey:HPSettingFontSizeAdjust];
        //NSLog(@"_currentFontSize = SETTING");
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
     SWRevealViewController *revealController = [self revealViewController];
    [self.navigationController.view removeGestureRecognizer:revealController.panGestureRecognizer];
    
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidBecomeActiveNotification
                                                  object:[UIApplication sharedApplication]];
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidEnterBackgroundNotification
                                                  object:[UIApplication sharedApplication]];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    NSLog(@"threadVC dealloc");
    
    [self.tableView removeObserver:self forKeyPath:@"contentOffset" context:(__bridge void *)self];
}

#pragma mark -
- (void)setActionButton {
    
    /*
    UIBarButtonItem *revealBI = [UIBarButtonItem barItemWithImage:[UIImage imageNamed:@"menu2.png"]
                                                             size:CGSizeMake(40.f, 40.f)
                                                           target:self
                                                           action:@selector(revealToggle:)];
     */
    
    self.navigationItem.leftBarButtonItem = [[HPRearViewController sharedRearVC] sharedRevealActionBI];
    
    _refreshButtonBI = [UIBarButtonItem barItemWithImage:[[UIImage imageNamed:@"home_refresh.png"] changeColor:[UIColor grayColor]]
                                              size:CGSizeMake(40.f, 40.f)
                                            target:self
                                            action:@selector(refresh:)];
    _refreshIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
    _refreshIndicatorBI = [[UIBarButtonItem alloc] initWithCustomView:_refreshIndicator];
    
    
    [_refreshIndicator setActivityIndicatorViewStyle:[HPTheme indicatorViewStyle]];
    
    _composeBI = [UIBarButtonItem barItemWithImage:[UIImage imageNamed:@"write.png"]
                                                              size:CGSizeMake(30.f, 30.f)
                                                            target:self
                                                            action:@selector(newThread:)];
    
    self.navigationItem.rightBarButtonItems = @[_composeBI,_refreshButtonBI];
}

#pragma mark - load

- (void)loadForum:(NSInteger)fid title:(NSString *)title {
    [Flurry logEvent:@"ThreadVC LoadForum" withParameters:@{@"fid":@(fid),@"title":title}];
    self.title = title;
    _current_fid = fid;
    
    [self.filterMenu updateWithFid:self.current_fid];
    [self refresh:[UIButton new]];
}

- (void)load:(LoadType)type
     refresh:(BOOL)refresh {

    [Flurry logEvent:@"ThreadVC Refresh" withParameters:@{@"type":@(type),@"forceRefresh":@(refresh)}];
    
    NSDictionary *filterParams = self.filterMenu.currentFilter;
    
    __weak typeof(self) weakSelf = self;
    [HPThread loadThreadsWithFid:_current_fid
                            page:_current_page
                    filterParams:filterParams
                    forceRefresh:refresh
                           block:^(NSArray *threads, NSError *error)
     {
         [weakSelf.refreshControl endRefreshing];
         if (!error) {
            
             if (type != LoadMore) {
                 
                 _threads = [NSMutableArray arrayWithArray:threads];
                 [weakSelf.tableView reloadData];
                 
                 if (type == ClickToRefresh) {
                     NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
                     [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:NO];
                 }
                 
             } else { // loadMore
                 
                 // 去重, O(50^2)
                 NSArray *oldThreads = [NSArray arrayWithArray:_threads];
                 BOOL isSame = NO;
                 for (HPThread *thread in threads) {
                     isSame = NO;
                     for (HPThread *oldthread in oldThreads) {
                         if (oldthread.tid == thread.tid) {
                             isSame = YES;
                             break;
                         }
                     }
                     if (!isSame) [_threads addObject:thread];
                 }
                
                 [weakSelf.tableView reloadData];
             }
             
             [weakSelf.tableView flashScrollIndicators];
             
         } else {
             
             if (error.code == NSURLErrorUserAuthenticationRequired) {
                 NSLog(@"重新登陆...");
                 if ([HPAccount isSetAccount]) {
                     [SVProgressHUD showWithStatus:@"重新登陆中..."];
                 }
             } else  if (error.code == HPERROR_NOT_DEFAULT_THREAD_SETTING_CODE) {
                 [UIAlertView showWithTitle:@"加载失败"
                                    message:@"返回结果为空, 可能是由于您设置了每页帖子15条, 而置顶帖超过15个, 前往个人中心修改为默认?"
                                    handler:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:S(@"http://%@/forum/memcp.php?action=profile&typeid=5", HPBaseURL)]];
                                    }];
             } else if (error.code == HPERROR_CRAWLER_CODE) {
                 HPCrawlerErrorContext *context = error.userInfo[@"context"];
                 [Flurry logEvent:@"Crawler_Error" withParameters:@{@"info":[NSString stringWithFormat:@"url:%@, html:%@", context.url, context.html], @"js": [[context.html hp_jsLinks] componentsJoinedByString:@", "]}];
                 [UIAlertView showWithTitle:@"加载失败"
                                    message:@"看看是不是论坛挂了或者是被运营商劫持了"
                                    handler:^(UIAlertView *alertView, NSInteger buttonIndex) {
                                        HPDebugCrawlerViewController *dvc = [HPDebugCrawlerViewController new];
                                        dvc.context = context;
                                        [self presentViewController:[HPCommon swipeableNVCWithRootVC:dvc] animated:YES completion:nil];
                                    }];
             } else {
                 [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
             }
         }
        
         if (type == PullToRefresh) {
             
         }
         
         switch (type) {
             case PullToRefresh:
                 [weakSelf.refreshControl endRefreshing];
                 break;
             case ClickToRefresh:
                 weakSelf.navigationItem.rightBarButtonItems = @[_composeBI,_refreshButtonBI];
                 break;
             case LoadMore:
                 [weakSelf loadMoreDone];
                 break;
             default:
                 break;
         }
         
         [weakSelf performSelector:@selector(addLoadMoreView) withObject:nil afterDelay:1.f];
                   
     }];
}


- (void)refresh:(id)sender {
    LoadType type = 0;
    
    if ([sender isKindOfClass:[UIRefreshControl class]]) {
        
        type = PullToRefresh;
        
    } else if ([sender isKindOfClass:[UIButton class]]) {
        
        type = ClickToRefresh;
        //NSLog(@"%@, %@", _composeBI,_refreshIndicatorBI);
        if (_composeBI && _refreshButtonBI) {
            self.navigationItem.rightBarButtonItems = @[_composeBI,_refreshIndicatorBI];
        }
        [_refreshIndicator startAnimating];
        
    } else {
        NSLog(@"unknown sender %@", sender);
    }
    
    NSLog(@"refresh...");
    _current_page = 1;
    [self load:type refresh:YES];
}

- (void)loadmore:(id)sender {
    _current_page = _current_page + 1;
    [self load:LoadMore];
}

- (void)load:(LoadType)type {
    [self load:type refresh:NO];
}


#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_threads count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    HPThread *thread = [_threads objectAtIndex:indexPath.row];
    
    static NSString *CellIdentifier = @"_HPThreadCell_";
    HPThreadCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[HPThreadCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
    }
    
    // configure
    cell.hp_delegate = self;
    [cell configure:thread];
    
    // MCSwipeTableViewCell
    [self addActionsForCell:cell forRowAtIndexPath:indexPath];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [HPThreadCell heightForCellWithThread:[_threads objectAtIndex:indexPath.row]];
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    HPThread *thread = [_threads objectAtIndex:indexPath.row];
    
    // mark read
    HPThreadCell *cell = (HPThreadCell *)[tableView cellForRowAtIndexPath:indexPath];
    [cell markRead];
    
    HPReadViewController *readVC =
    [[HPReadViewController alloc] initWithThread:thread];
    [self.navigationController pushViewController:readVC animated:YES];
}

#pragma mark - NSKeyValueObserving

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if ((__bridge id)context != self) {
        return;
    }
    if (!_loadingMoreView) {
        return;
    }
    
    CGRect f = _loadingMoreView.frame;
    f.origin.y = [self tableViewHeight];
    _loadingMoreView.frame = f;
}

#pragma mark - loadMore & UIScrollViewDelegate

- (void)addLoadMoreView {
    
    if (_threads.count == 0) return;
    
    if (_loadingMoreView == nil) {
        _loadingMoreView = [[EGORefreshTableFooterView alloc] initWithFrame:CGRectMake(0.0f, [self tableViewHeight], CGRectGetWidth([[UIScreen mainScreen] bounds]), 600.0f)];
		_loadingMoreView.backgroundColor = [UIColor clearColor];
		[self.tableView addSubview:_loadingMoreView];
		self.tableView.showsVerticalScrollIndicator = YES;
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView{
	
	if (scrollView.isDragging) {
        float endOfTable = [self endOfTableView:scrollView];
        if (_loadingMoreView.state == EGOOPullRefreshPulling && endOfTable < 0.0f && endOfTable > TRIGGER_OFFSET_Y && !_loadingMore) {
			[_loadingMoreView setState:EGOOPullRefreshNormal];
		} else if (_loadingMoreView.state == EGOOPullRefreshNormal && endOfTable < TRIGGER_OFFSET_Y && !_loadingMore) {
			[_loadingMoreView setState:EGOOPullRefreshPulling];
		}
	}
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    //NSLog(@"scrollViewWillEndDragging");
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate{
	
    if ([self endOfTableView:scrollView] <= TRIGGER_OFFSET_Y && !_loadingMore) {
        _loadingMore = YES;
        [self loadmore:nil];
        [_loadingMoreView setState:EGOOPullRefreshLoading];
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:0.2];
        UIEdgeInsets edgeInset = UIEdgeInsetsMake(0.0f, 0.0f, 60.0f, 0.0f);
        if (IOS7_OR_LATER) {
            edgeInset.top += 64.0f;
        }
        [self.tableView setContentInset:edgeInset];
        [UIView commitAnimations];
	}
}

- (void)loadMoreDone {
	
	_loadingMore = NO;
	
	[UIView beginAnimations:nil context:NULL];
	[UIView setAnimationDuration:.3];
    UIEdgeInsets edgeInset = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, 0.0f);
    if (IOS7_OR_LATER) edgeInset.top = 64.0f;
	[self.tableView setContentInset:edgeInset];
	[UIView commitAnimations];
    
    if ([_loadingMoreView state] != EGOOPullRefreshNormal) {
        [_loadingMoreView setState:EGOOPullRefreshNormal];
    }
}

- (float)tableViewHeight {
    // return height of table view
    return [self.tableView contentSize].height;
}

- (float)endOfTableView:(UIScrollView *)scrollView {
    return [self tableViewHeight] - scrollView.bounds.size.height - scrollView.bounds.origin.y;
}



#pragma mark - MCSwipeTableViewCellDelegate

// When the user starts swiping the cell this method is called
- (void)swipeTableViewCellDidStartSwiping:(MCSwipeTableViewCell *)cell {
    //NSLog(@"Did start swiping the cell!");
}

// When the user ends swiping the cell this method is called
- (void)swipeTableViewCellDidEndSwiping:(MCSwipeTableViewCell *)cell {
    //NSLog(@"Did end swiping the cell!");
}

// When the user is dragging, this method is called and return the dragged percentage from the border
- (void)swipeTableViewCell:(MCSwipeTableViewCell *)cell didSwipWithPercentage:(CGFloat)percentage {
    //NSLog(@"Did swipe with percentage : %f", percentage);
}

- (void)addActionsForCell:(HPThreadCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    
    [cell setDelegate:self];
    if (indexPath.row % 2 == 0) {
        [cell.contentView setBackgroundColor:[HPTheme oddCellColor]];
        [cell setDefaultColor:[HPTheme oddCellColor]];
    } else {
        [cell.contentView setBackgroundColor:[HPTheme evenCellColor]];
        [cell setDefaultColor:[HPTheme evenCellColor]];
    }
    
    cell.shouldAnimateIcons = YES;
    cell.firstTrigger = 0.18f;
    cell.secondTrigger = 0.40f;
    
    [cell setSwipeGestureWithView:[cell viewWithImageName:@"last.png"]
                            color:[HPTheme threadJumpColor]
                             mode:MCSwipeTableViewCellModeSwitch
                            state:MCSwipeTableViewCellState3
                  completionBlock:
     ^(MCSwipeTableViewCell *cell, MCSwipeTableViewCellState state, MCSwipeTableViewCellMode mode) {
         
         HPThread *thread = [_threads objectAtIndex:[self.tableView indexPathForCell:cell].row];
         
         HPReadViewController *rvc = [[HPReadViewController alloc]
                                      initWithThread:thread
                                      page:NSIntegerMax
                                      forceFullPage:YES];
         
         [self.navigationController pushViewController:rvc animated:YES];
         
         [Flurry logEvent:@"ThreadVC SwipeToJump"];
     }];
    
    [cell setSwipeGestureWithView:[cell viewWithImageName:@"clock.png"]
                            color:[HPTheme threadPreloadColor]
                             mode:MCSwipeTableViewCellModeSwitch
                            state:MCSwipeTableViewCellState4
                  completionBlock:
     ^(MCSwipeTableViewCell *cell, MCSwipeTableViewCellState state, MCSwipeTableViewCellMode mode) {
         
         HPThread *thread = [_threads objectAtIndex:[self.tableView indexPathForCell:cell].row];
         NSLog(@"background open thread %@", thread.title);

         [(HPThreadCell *)cell markRead];
         [[HPCache sharedCache] readThread:thread];
         [HPIndecator show];
         
         
         [[HPCache sharedCache] cacheBgThread:thread block:^(NSError *error) {
             [HPIndecator dismiss];
         }];
         
         [Flurry logEvent:@"ThreadVC SwipeToPreload"];
         
         if ([NSStandardUserDefaults boolForKey:kHPHomeTip4Bg or:YES]) {
             [UIAlertView showConfirmationDialogWithTitle:@"提示"
                                                  message:@"帖子已预载入\n在「待读」界面查看"
                                                  handler:^(UIAlertView *alertView, NSInteger buttonIndex)
              {
                  if (buttonIndex != [alertView cancelButtonIndex]) {
                      [NSStandardUserDefaults saveBool:NO forKey:kHPHomeTip4Bg];
                  }
              }];
         }
     }];
    
}


#pragma mark - actions
- (void)revealToggle:(id)sender {
    
    //NSLog(NSStringFromUIEdgeInsets(self.tableView.contentInset));
    [self.revealViewController revealToggle:sender];
}

- (void)newThread:(id)sender {
    HPNewThreadViewController *tvc = [[HPNewThreadViewController alloc] initWithFourm:_current_fid delegate:self];
    
    [self presentViewController:[HPCommon swipeableNVCWithRootVC:tvc] animated:YES completion:nil];
    
    [Flurry logEvent:@"ThreadVC NewThread"];
}

- (void)compositionDoneWithType:(ActionType)type error:(NSError *)error {
    [self refresh:[UIButton new]];
}

#pragma mark - login

- (void)loginError:(NSNotification *)notification
{
    NSError *error = [[notification userInfo] objectForKey:@"error"];
    [SVProgressHUD showErrorWithStatus:[error localizedDescription]];
    [Flurry logEvent:@"ThreadVC AutoLogin" withParameters:@{@"error":[error localizedDescription]}];
}

- (void)loginSuccess:(NSNotification *)notification
{
    [SVProgressHUD showSuccessWithStatus:@"登陆成功"];
    [self refresh:[UIButton new]];
    [Flurry logEvent:@"ThreadVC AutoLogin" withParameters:@{@"error":@""}];
}

#pragma mark - 自动刷新
- (void)UIApplicationDidEnterBackgroundNotification:(NSNotification *)notification
{
    self.lastEnterBackgroundDate = [NSDate new];
}

- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification
{
    if (!self.lastEnterBackgroundDate) {
        return;
    }
    
    // 离开超过10分钟, 回来时自动刷新
    NSTimeInterval interval = [[NSDate new] timeIntervalSinceDate:self.lastEnterBackgroundDate];
    if (interval > 10 * 60) {
        [self refresh:[UIButton new]];
    }
    
    self.lastEnterBackgroundDate = nil;
}

#pragma mark - theme
- (void)themeDidChanged {
    [self setActionButton];
    [self.tableView reloadData];
    [self.tableView setBackgroundColor:[HPTheme backgroundColor]];
}

#pragma mark - 
- (void)didClickAvatar:(HPUser *)user {
    HPUserViewController *uvc = [HPUserViewController new];
    
    NSStringEncoding gbkEncoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    uvc.username = [user.username stringByAddingPercentEscapesUsingEncoding:gbkEncoding];
    
    [self.navigationController pushViewController:uvc animated:YES];
}

@end
