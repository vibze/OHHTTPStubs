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

@interface ThreadingTests : XCTestCase
{
    NSThread* _callingThread;
    XCTestExpectation* _connectionFinishedExpectation;
}
@end

static NSTimeInterval kResponseTimeTolerence = 0.5f;

@implementation ThreadingTests

-(void)setUp
{
    [super setUp];
    [OHHTTPStubs removeAllStubs];
}

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
    
    _connectionFinishedExpectation = [self expectationWithDescription:@"NSURLConnection did finish (with error or success)"];
    __block NSURLConnection* _connection;

    NSOperationQueue* q = [[NSOperationQueue alloc] init];
    [q addOperationWithBlock:^{
        _callingThread = [NSThread currentThread];
        XCTAssertNotEqual(_callingThread, [NSThread mainThread], @"Test is not working as designed. It should call the request from a thread other than the main");
        NSURLRequest* req = [NSURLRequest requestWithURL:testURL];
        _connection = [NSURLConnection connectionWithRequest:req delegate:self];

        CFRunLoopRun(); // For the thread's runloop to run, so that the NSURLConnection request is executed.
    }];

    [self waitForExpectationsWithTimeout:kResponseTimeTolerence handler:nil];
    
    // in case we timed out before the end of the request (test failed), cancel the request to avoid further delegate method calls
    [_connection cancel];
}

///////////////////////////////////////////////////////////////////////////////////////


-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    XCTAssertEqual(_callingThread, [NSThread currentThread], @"%@ not called on the calling thread", NSStringFromSelector(_cmd));
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    XCTAssertEqual(_callingThread, [NSThread currentThread], @"%@ not called on the calling thread", NSStringFromSelector(_cmd));
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    XCTAssertEqual(_callingThread, [NSThread currentThread], @"%@ not called on the calling thread", NSStringFromSelector(_cmd));
    [_connectionFinishedExpectation fulfill];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    XCTAssertEqual(_callingThread, [NSThread currentThread], @"%@ not called on the calling thread", NSStringFromSelector(_cmd));
    [_connectionFinishedExpectation fulfill];
}

@end
