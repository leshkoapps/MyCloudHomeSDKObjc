//
//  MCHRequestsCache.m
//  MyCloudHomeSDKObjc
//
//  Created by Artem on 3/2/21.
//

#import "MCHRequestsCache.h"
#import "MCHAPIClientRequest.h"

@interface MCHRequestsCache()

@property (nonatomic, strong) NSMutableArray<MCHAPIClientRequest *> *cancellableRequests;

@property (nonatomic, strong) NSRecursiveLock *stateLock;

@end


@implementation MCHRequestsCache

- (instancetype)init {
    self = [super init];
    if (self) {
        self.cancellableRequests = [NSMutableArray<MCHAPIClientRequest *> new];
        self.stateLock = [NSRecursiveLock new];
    }
    return self;
}

- (NSArray<MCHAPIClientRequest *> * _Nullable)cachedCancellableRequestsWithURLTaskIdentifier:(NSUInteger)URLTaskIdentifier{
    NSMutableArray<MCHAPIClientRequest *> *requests = [NSMutableArray<MCHAPIClientRequest *> new];
    [self.stateLock lock];
    for (id<MCHAPIClientCancellableRequest> obj in self.cancellableRequests) {
        if ([obj isKindOfClass:[MCHAPIClientRequest class]] && ((MCHAPIClientRequest *)obj).URLTaskIdentifier == URLTaskIdentifier) {
            [requests addObject:obj];
        }
    }
    [self.stateLock unlock];
    return requests;
}

- (NSArray<MCHAPIClientRequest *> * _Nullable)allCachedCancellableRequestsWithURLTasks{
    NSMutableArray *result = [NSMutableArray<MCHAPIClientRequest *> new];
    [self.stateLock lock];
    for (id<MCHAPIClientCancellableRequest> obj in self.cancellableRequests) {
        if ([obj isKindOfClass:[MCHAPIClientRequest class]] && ((MCHAPIClientRequest *)obj).URLTaskIdentifier > 0) {
            [result addObject:obj];
        }
    }
    [self.stateLock unlock];
    return result;
}

- (MCHAPIClientRequest *)createCachedCancellableRequest{
    MCHAPIClientRequest *clientRequest = [[MCHAPIClientRequest alloc] init];
    [self addCancellableRequestToCache:clientRequest];
    return clientRequest;
}

- (void)addCancellableRequestToCache:(MCHAPIClientRequest * _Nonnull)request{
    NSParameterAssert([request isKindOfClass:[MCHAPIClientRequest class]]);
    if ([request isKindOfClass:[MCHAPIClientRequest class]] == NO) {
        return;
    }
    
    [self.stateLock lock];
    [self.cancellableRequests addObject:request];
    NSParameterAssert(self.cancellableRequests.count < 100);
    MCHLog(@"MCH_REQUEST_ADD: %@",@(self.cancellableRequests.count));
    
    MCHMakeWeakSelf;
    MCHMakeWeakReference(request);
    [(MCHAPIClientRequest *)request setCancelBlock:^{
        [weakSelf removeCancellableRequestFromCache:weak_request];
    }];
    
    [self.stateLock unlock];
}

- (void)removeCancellableRequestFromCache:(id<MCHAPIClientCancellableRequest> _Nonnull)request{
    if ([request isKindOfClass:[MCHAPIClientRequest class]]) {
        MCHAPIClientRequest *clientRequest = (MCHAPIClientRequest *)request;
        [self removeCancellableRequestFromCache:clientRequest.childRequest];
        clientRequest.childRequest = nil;
    }
    
    if (request != nil) {
        [self.stateLock lock];
        [self.cancellableRequests removeObject:request];
        MCHLog(@"MCH_REQUEST_REMOVE: %@",@(self.cancellableRequests.count));
        [self.stateLock unlock];
    }
}

- (void)cancelAndRemoveAllCachedRequests {
    [self.stateLock lock];
    for (id<MCHAPIClientCancellableRequest>request in self.cancellableRequests) {
        [MCHRequestsCache removeCancelBlockForRequest:request];
        if ([request respondsToSelector:@selector(cancel)]) {
            [request cancel];
        }
    }
    [self.cancellableRequests removeAllObjects];
    [self.stateLock unlock];
}

+ (void)removeCancelBlockForRequest:(id)request {
    if ([request isKindOfClass:[MCHAPIClientRequest class]] == NO) {
        return;
    }
    MCHAPIClientRequest *clientRequest = (MCHAPIClientRequest *)request;
    [clientRequest setCancelBlock:nil];
    [MCHRequestsCache removeCancelBlockForRequest:clientRequest.childRequest];
}

@end
