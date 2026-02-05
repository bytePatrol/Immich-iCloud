import XCTest
@testable import Immich_iCloud

final class RetryPolicyTests: XCTestCase {

    // MARK: - Delay Calculation

    func testDefaultDelays() {
        let policy = RetryPolicy()

        // Attempt 0: 1s * 2^0 = 1s
        XCTAssertEqual(policy.delay(forAttempt: 0), 1.0, accuracy: 0.01)
        // Attempt 1: 1s * 2^1 = 2s
        XCTAssertEqual(policy.delay(forAttempt: 1), 2.0, accuracy: 0.01)
        // Attempt 2: 1s * 2^2 = 4s
        XCTAssertEqual(policy.delay(forAttempt: 2), 4.0, accuracy: 0.01)
        // Attempt 3: 1s * 2^3 = 8s
        XCTAssertEqual(policy.delay(forAttempt: 3), 8.0, accuracy: 0.01)
        // Attempt 4: 1s * 2^4 = 16s
        XCTAssertEqual(policy.delay(forAttempt: 4), 16.0, accuracy: 0.01)
    }

    func testDelayCappedAtMax() {
        let policy = RetryPolicy(maxRetries: 10, baseDelay: 1.0, maxDelay: 30.0)

        // Attempt 5: 1s * 2^5 = 32s → capped to 30s
        XCTAssertEqual(policy.delay(forAttempt: 5), 30.0, accuracy: 0.01)
        // Attempt 10: would be 1024s → capped to 30s
        XCTAssertEqual(policy.delay(forAttempt: 10), 30.0, accuracy: 0.01)
    }

    func testCustomBaseDelay() {
        let policy = RetryPolicy(maxRetries: 3, baseDelay: 2.0, maxDelay: 60.0)

        // Attempt 0: 2s * 2^0 = 2s
        XCTAssertEqual(policy.delay(forAttempt: 0), 2.0, accuracy: 0.01)
        // Attempt 1: 2s * 2^1 = 4s
        XCTAssertEqual(policy.delay(forAttempt: 1), 4.0, accuracy: 0.01)
        // Attempt 2: 2s * 2^2 = 8s
        XCTAssertEqual(policy.delay(forAttempt: 2), 8.0, accuracy: 0.01)
    }

    // MARK: - Retryability

    func testURLTimeoutIsRetryable() {
        let error = URLError(.timedOut)
        XCTAssertTrue(RetryPolicy.isRetryable(error))
    }

    func testURLNotConnectedIsRetryable() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertTrue(RetryPolicy.isRetryable(error))
    }

    func testURLConnectionLostIsRetryable() {
        let error = URLError(.networkConnectionLost)
        XCTAssertTrue(RetryPolicy.isRetryable(error))
    }

    func testURLBadURLIsNotRetryable() {
        let error = URLError(.badURL)
        XCTAssertFalse(RetryPolicy.isRetryable(error))
    }

    func testHTTP500IsRetryable() {
        let error = AppError.immichConnectionFailed("HTTP 500: Internal Server Error")
        XCTAssertTrue(RetryPolicy.isRetryable(error))
    }

    func testHTTP429IsRetryable() {
        let error = AppError.immichConnectionFailed("HTTP 429: Too Many Requests")
        XCTAssertTrue(RetryPolicy.isRetryable(error))
    }

    func testHTTP404IsNotRetryable() {
        let error = AppError.immichConnectionFailed("HTTP 404: Not Found")
        XCTAssertFalse(RetryPolicy.isRetryable(error))
    }

    func testHTTP401IsNotRetryable() {
        let error = AppError.immichConnectionFailed("HTTP 401: Unauthorized")
        XCTAssertFalse(RetryPolicy.isRetryable(error))
    }

    func testGenericErrorIsNotRetryable() {
        struct CustomError: Error {}
        XCTAssertFalse(RetryPolicy.isRetryable(CustomError()))
    }

    // MARK: - Policy Defaults

    func testDefaultPolicyValues() {
        let policy = RetryPolicy()
        XCTAssertEqual(policy.maxRetries, 3)
        XCTAssertEqual(policy.baseDelay, 1.0, accuracy: 0.01)
        XCTAssertEqual(policy.maxDelay, 30.0, accuracy: 0.01)
    }
}
