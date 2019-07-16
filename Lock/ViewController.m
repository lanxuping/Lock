//
//  ViewController.m
//  Lock
//
//  Created by Lan Xuping on 2019/7/15.
//  Copyright © 2019 Lan Xuping. All rights reserved.
//

#import "ViewController.h"
#import <libkern/OSAtomic.h>
#import <pthread.h>
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
//    [self testRecursiveLock];
    // Do any additional setup after loading the view.
    [self testpthread_mutex];
}

- (void)testNSLock {
    //主线程中
    NSLock *lock = [[NSLock alloc] init];
    //线程1
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [lock lock];
        NSLog(@"线程1");
        sleep(10);
        [lock unlock];
        NSLog(@"线程1解锁成功");
    });
    
    //线程2
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);//以保证让线程2的代码后执行
//        [lock lock]; //直接加锁
//        [lock tryLock]; //尝试加锁，如果加锁失败则直接执行下面代码
        if ([lock lockBeforeDate:[NSDate dateWithTimeIntervalSinceNow:10]]) { //在指定时间点前尝试加锁，如果失败则直接执行下面代码
            NSLog(@"线程2");
            [lock unlock];
        } else {
            NSLog(@"失败");
        }
    });
    
    /*log
     线程 1 中的 lock 锁上了，所以线程 2 中的 lock 加锁失败，阻塞线程 2，但 2 s 后线程 1 中的 lock 解锁，线程 2 就立即加锁成功，执行线程 2 中的后续代码。
     
     线程1  线程2  线程1解锁成功
     */
}
- (void)testNSConditionLock { //条件锁
    NSConditionLock *lock = [[NSConditionLock alloc] initWithCondition:0];
    
    //      NSConditionLock 可以称为条件锁，只有 condition 参数与初始化时候的 condition 相等，lock 才能正确进行加锁操作
    //      而 unlockWithCondition: 并不是当 Condition 符合条件时才解锁，而是解锁之后，修改 Condition 的值
    //线程1
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [lock lockWhenCondition:1];
        NSLog(@"线程1");
        sleep(2);
        [lock unlock];
    });
    
    //线程2
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);//以保证让线程2的代码后执行
        if ([lock tryLockWhenCondition:0]) {
            NSLog(@"线程2");
            [lock unlockWithCondition:2];
            NSLog(@"线程2解锁成功");
        } else {
            NSLog(@"线程2尝试加锁失败");
        }
    });
    
    //线程3
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(2);//以保证让线程2的代码后执行
        if ([lock tryLockWhenCondition:2]) {
            NSLog(@"线程3");
            [lock unlock];
            NSLog(@"线程3解锁成功");
        } else {
            NSLog(@"线程3尝试加锁失败");
        }
    });
    
    //线程4
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(3);//以保证让线程2的代码后执行
        if ([lock tryLockWhenCondition:2]) {
            NSLog(@"线程4");
            [lock unlockWithCondition:1];
            NSLog(@"线程4解锁成功");
        } else {
            NSLog(@"线程4尝试加锁失败");
        }
    });
    
    
    /*
     2019-07-15 16:05:44.998770+0800 Lock[3166:280965] 线程2
     2019-07-15 16:05:44.999186+0800 Lock[3166:280965] 线程2解锁成功
     2019-07-15 16:05:46.001335+0800 Lock[3166:280967] 线程3
     2019-07-15 16:05:46.001514+0800 Lock[3166:280967] 线程3解锁成功
     2019-07-15 16:05:47.000005+0800 Lock[3166:280964] 线程4
     2019-07-15 16:05:47.000253+0800 Lock[3166:280964] 线程4解锁成功
     2019-07-15 16:05:47.000259+0800 Lock[3166:280966] 线程1
     
     上面代码先输出了 ”线程 2“，因为线程 1 的加锁条件不满足，初始化时候的 condition 参数为 0，而加锁条件是 condition 为 1，所以加锁失败。locakWhenCondition 与 lock 方法类似，加锁失败会阻塞线程，所以线程 1 会被阻塞着，而 tryLockWhenCondition 方法就算条件不满足，也会返回 NO，不会阻塞当前线程。
     回到上面的代码，线程 2 执行了 [lock unlockWithCondition:2]; 所以 Condition 被修改成了 2。
     而线程 3 的加锁条件是 Condition 为 2， 所以线程 3 才能加锁成功，线程 3 执行了 [lock unlock]; 解锁成功且不改变 Condition 值。
     线程 4 的条件也是 2，所以也加锁成功，解锁时将 Condition 改成 1。这个时候线程 1 终于可以加锁成功，解除了阻塞。
     从上面可以得出，NSConditionLock 还可以实现任务之间的依赖。

     
     */
}
- (void)testRecursiveLock {
    /*NSRecursiveLock 是递归锁，他和 NSLock 的区别在于，NSRecursiveLock 可以在一个线程中重复加锁（反正单线程内任务是按顺序执行的，不会出现资源竞争问题），NSRecursiveLock 会记录上锁和解锁的次数，当二者平衡的时候，才会释放锁，其它线程才可以上锁成功。*/
    NSRecursiveLock *lock = [[NSRecursiveLock alloc] init];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        static void (^RecursiveBlock)(int);
        RecursiveBlock = ^(int value){
            [lock lock];
            if (value > 0) {
                NSLog(@"%d",value);
                RecursiveBlock(value-1);
            }
            [lock unlock];
        };
        RecursiveBlock(2);
    });
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);
        [lock lock];
        NSLog(@"?");
        [lock unlock];
    });
    /*
     2019-07-15 17:58:34.986222+0800 Lock[5118:423742] 2
     2019-07-15 17:58:34.986377+0800 Lock[5118:423742] 1
     2019-07-15 17:58:35.991068+0800 Lock[5118:423745] ?
     
    如果用 NSLock 的话，lock 先锁上了，但未执行解锁的时候，就会进入递归的下一层，而再次请求上锁，阻塞了该线程，线程被阻塞了，自然后面的解锁代码不会执行，而形成了死锁。而 NSRecursiveLock 递归锁就是为了解决这个问题*/
}
- (void)testNSCondition {
    NSCondition *lock = [[NSCondition alloc] init];
    NSMutableArray *array = [[NSMutableArray alloc] init];
    //线程1
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [lock lock];
        while (!array.count) {
            [lock wait];
        }
        [array removeAllObjects];
        NSLog(@"array removeAllObjects");
        [lock unlock];
    });
    
    //线程2
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        sleep(1);//以保证让线程2的代码后执行
        [lock lock];
        [array addObject:@1];
        NSLog(@"array addObject:@1");
        [lock signal];
        [lock unlock];
    });
}
- (void)testSemaphore {
    dispatch_semaphore_t sem = dispatch_semaphore_create(1);
    dispatch_time_t overtime = dispatch_time(DISPATCH_TIME_NOW, 3*NSEC_PER_SEC);
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        dispatch_semaphore_wait(sem, overtime);
        NSLog(@"线程1");
        sleep(2);
        dispatch_semaphore_signal(sem);
    });
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        sleep(1);
        dispatch_semaphore_wait(sem, overtime);
        NSLog(@"线程2");
        dispatch_semaphore_signal(sem);
    });
}
- (void)testOSSpinLock {
    /*
     OSSpinLock 是一种自旋锁，也只有加锁，解锁，尝试加锁三个方法。和 NSLock 不同的是 NSLock 请求加锁失败的话，会先轮询，但一秒过后便会使线程进入 waiting 状态，等待唤醒。而 OSSpinLock 会一直轮询，等待时会消耗大量 CPU 资源，不适用于较长时间的任务。
     */
    __block OSSpinLock theLock = OS_SPINLOCK_INIT;
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        OSSpinLockLock(&theLock);
        NSLog(@"线程1");
        sleep(10);
        OSSpinLockUnlock(&theLock);
        NSLog(@"线程1 ok");
    });
    
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        sleep(1);
        OSSpinLockLock(&theLock);
        NSLog(@"线程2");
        OSSpinLockUnlock(&theLock);
    });
    /*
     log
     2019-07-16 11:46:53.023508+0800 Lock[7318:646881] 线程1
     2019-07-16 11:47:03.024814+0800 Lock[7318:646881] 线程1 ok
     2019-07-16 11:47:03.146315+0800 Lock[7318:646879] 线程2
     拿上面的输出结果和上文 NSLock 的输出结果做对比，会发现 sleep(10) 的情况，OSSpinLock 中的“线程 2”并没有和”线程 1 ok“在一个时间输出，而 NSLock 这里是同一时间输出，而是有一点时间间隔，所以 OSSpinLock 一直在做着轮询，而不是像 NSLock 一样先轮询，再 waiting 等唤醒。
     */
}


static pthread_mutex_t theLock;
- (void)testpthread_mutex {
    pthread_mutex_init(&theLock, NULL); //首先是第一个方法，这是初始化一个锁，__restrict 为互斥锁的类型，传 NULL 为默认类型，一共有 4 类型。
    /*
     PTHREAD_MUTEX_NORMAL 缺省类型，也就是普通锁。当一个线程加锁以后，其余请求锁的线程将形成一个等待队列，并在解锁后先进先出原则获得锁。
     
     PTHREAD_MUTEX_ERRORCHECK 检错锁，如果同一个线程请求同一个锁，则返回 EDEADLK，否则与普通锁类型动作相同。这样就保证当不允许多次加锁时不会出现嵌套情况下的死锁。
     
     PTHREAD_MUTEX_RECURSIVE 递归锁，允许同一个线程对同一个锁成功获得多次，并通过多次 unlock 解锁。
     
     PTHREAD_MUTEX_DEFAULT 适应锁，动作最简单的锁类型，仅等待解锁后重新竞争，没有等待队列。
     */
    
    pthread_t thread;
    pthread_create(&thread, NULL, threadMethod1, NULL);
    
    pthread_t thread2;
    pthread_create(&thread2, NULL, threadMethod2, NULL);
}
void *threadMethod1() {
    pthread_mutex_lock(&theLock);
    printf("线程1 \n");
    sleep(2);
    pthread_mutex_unlock(&theLock);
    printf("线程1 解锁成功 \n");
    return 0;
}

void *threadMethod2() {
    sleep(1);
    pthread_mutex_lock(&theLock);
    printf("线程2 \n");
    pthread_mutex_unlock(&theLock);
    return 0;
}
@end
