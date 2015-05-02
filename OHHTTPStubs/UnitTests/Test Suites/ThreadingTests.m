/***********************************************************************************
 *
 * Copyright (c) 2012 Olivier Halligon
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 ***********************************************************************************/


#import <XCTest/XCTest.h>
#import "OHHTTPStubs.h"
#import <objc/runtime.h>

@interface ThreadingTests : XCTestCase
{
    NSThread* _callingThread;
    XCTestExpectation* _connectionFinishedExpectation;
}
@end

@interface NSURLProtocolClientProxy : NSObject
-(instancetype)initWithMethodInvocationHandler:(void(^)(NSInvocation*))block;
-(void)installAsMockForClass:(Class)cls;
-(void)uninstallAsMockForClass:(Class)cls;
@end




@implementation ThreadingTests

-(void)setUp
{
    [super setUp];
    [OHHTTPStubs removeAllStubs];
}

///////////////////////////////////////////////////////////////////////////////////////

/*
 According to
 https://developer.apple.com/library/prerelease/ios/samplecode/CustomHTTPProtocol/Listings/Read_Me_About_CustomHTTPProtocol_txt.html :
 
 « In addition, an NSURLProtocol subclass is expected to call the various methods of the NSURLProtocolClient protocol from the client thread »
 
 */

-(void)test_DelegateThreadSameAsCallingThread
{
    NSData* testData = [NSStringFromSelector(_cmd) dataUsingEncoding:NSUTF8StringEncoding];
    NSURL* testURL = [NSURL URLWithString:@"http://www.iana.org/domains/example/"];
    
    [OHHTTPStubs stubRequestsPassingTest:^BOOL(NSURLRequest *request) {
        return [request.URL isEqual:testURL];
    } withStubResponse:^OHHTTPStubsResponse *(NSURLRequest *request) {
        return [OHHTTPStubsResponse responseWithData:testData
                                          statusCode:200
                                             headers:nil];
    }];
    
    NSURLProtocolClientProxy* clientProxy = [[NSURLProtocolClientProxy alloc] initWithMethodInvocationHandler:^(NSInvocation *invocation) {
        NSString* methodName = NSStringFromSelector(invocation.selector);
        NSLog(@"Invoked method %@ on NSURLProtocolClient", methodName);
        XCTAssertEqualObjects(_callingThread, [NSThread currentThread], @"Method %@ not called on the calling thread!", methodName);
    }];
    Class stubsProtocolClass = NSClassFromString(@"OHHTTPStubsProtocol");
    [clientProxy installAsMockForClass:stubsProtocolClass];
    
    XCTestExpectation* expectation = [self expectationWithDescription:@"Request Completed"];
    [[[NSOperationQueue alloc] init] addOperationWithBlock:^{
        _callingThread = [NSThread currentThread];
        NSAssert(_callingThread != [NSThread mainThread], @"Test is not working as designed. It should call the request from a thread other than the main");
        NSURLRequest* req = [NSURLRequest requestWithURL:testURL];
        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
        {
            [expectation fulfill];
        }];
        
        CFRunLoopRun();
    }];
    
    [self waitForExpectationsWithTimeout:1.0 handler:nil];

    [clientProxy uninstallAsMockForClass:stubsProtocolClass];
}


@end





///////////////////////////////////////////////////////////////////////////////////////
// MARK: Mocking

/**
 * NOTE: We could probably have used something like OCMock here, but I was not sure that
 *       I wanted to import a whole mocking framework like this *just* for one Unit Test.
 *
 *       If we need more mocking in future tests, one may reconsider importing it in the future.
 */


@implementation NSURLProtocolClientProxy
{
    void(^ _invocationBlock)(NSInvocation*);
    id<NSURLProtocolClient> _realClient;
    id<NSURLProtocolClient>(*_originalClientImplementation)(id, SEL);
}

-(instancetype)initWithMethodInvocationHandler:(void(^)(NSInvocation*))block;
{
    self = [super init];
    _invocationBlock = block;
    return self;
}
- (NSMethodSignature*)methodSignatureForSelector:(SEL)selector
{
    NSMethodSignature* signature = [super methodSignatureForSelector:selector];
    if (!signature) {
        signature = [(NSObject*)_realClient methodSignatureForSelector:selector];
    }
    return signature;
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    if ([_realClient respondsToSelector:[anInvocation selector]]) {
        if (_invocationBlock) _invocationBlock(anInvocation);
        [anInvocation invokeWithTarget:_realClient];
    } else {
        [super forwardInvocation:anInvocation];
    }
}

-(void)installAsMockForClass:(Class)cls
{
    if (_originalClientImplementation != nil) return;
    
    SEL selector = @selector(client);
    Method method = class_getInstanceMethod(cls, selector);
    _originalClientImplementation = (id<NSURLProtocolClient>(*)(id,SEL))method_getImplementation(method);
    IMP newImpl = imp_implementationWithBlock(^id(id blockSelf) {
        _realClient = _originalClientImplementation(blockSelf, selector);
        return self;
    });
    if (!class_addMethod(cls, selector, newImpl, method_getTypeEncoding(method))) {
        method_setImplementation(method, newImpl);
    }
}

-(void)uninstallAsMockForClass:(Class)cls
{
    if (_originalClientImplementation == nil) return;
    
    SEL selector = @selector(client);
    Method method = class_getInstanceMethod(cls, selector);
    IMP mockImpl = method_getImplementation(method);
    imp_removeBlock(mockImpl);
    method_setImplementation(method, (IMP)_originalClientImplementation);
    _originalClientImplementation = nil;
}

@end



