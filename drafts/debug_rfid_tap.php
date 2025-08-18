<?php
// /api/debug_rfid_tap.php - Debug version to find the issue
error_reporting(E_ALL);
ini_set('display_errors', 0); // Don't display errors in output
ini_set('log_errors', 1);

// Set JSON header first
header('Content-Type: application/json');

// Test 1: Basic PHP functionality
try {
    $debug_info = [
        'php_version' => phpversion(),
        'current_time' => date('Y-m-d H:i:s'),
        'request_method' => $_SERVER['REQUEST_METHOD'] ?? 'unknown',
        'content_type' => $_SERVER['CONTENT_TYPE'] ?? 'unknown'
    ];
    
    // Test 2: Check if required files exist
    $file_checks = [
        'database_config' => file_exists('../config/database.php'),
        'email_functions' => file_exists('../includes/email_functions.php')
    ];
    
    // Test 3: Try to include required files
    $include_errors = [];
    
    if ($file_checks['database_config']) {
        try {
            require_once '../config/database.php';
            $include_errors['database'] = 'OK';
        } catch (Exception $e) {
            $include_errors['database'] = 'ERROR: ' . $e->getMessage();
        }
    } else {
        $include_errors['database'] = 'File not found: ../config/database.php';
    }
    
    if ($file_checks['email_functions']) {
        try {
            require_once '../includes/email_functions.php';
            $include_errors['email_functions'] = 'OK';
        } catch (Exception $e) {
            $include_errors['email_functions'] = 'ERROR: ' . $e->getMessage();
        }
    } else {
        $include_errors['email_functions'] = 'File not found: ../includes/email_functions.php';
    }
    
    // Test 4: Check database connection
    $db_status = 'Not tested';
    if ($include_errors['database'] === 'OK') {
        try {
            if (function_exists('getDB')) {
                $db = getDB();
                $db_status = 'Connected successfully';
            } else {
                $db_status = 'getDB() function not found';
            }
        } catch (Exception $e) {
            $db_status = 'Connection failed: ' . $e->getMessage();
        }
    }
    
    // Test 5: Check email functions
    $email_functions_status = [];
    if ($include_errors['email_functions'] === 'OK') {
        $email_functions_status['sendBookingStatusEmail'] = function_exists('sendBookingStatusEmail') ? 'Found' : 'Missing';
        $email_functions_status['getStatusFromTapCount'] = function_exists('getStatusFromTapCount') ? 'Found' : 'Missing';
    }
    
    // Test 6: Process actual request if POST
    $request_data = null;
    $request_status = 'Not POST request';
    
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = file_get_contents('php://input');
        $request_data = json_decode($input, true);
        
        if (json_last_error() === JSON_ERROR_NONE) {
            $request_status = 'JSON parsed successfully';
        } else {
            $request_status = 'JSON parse error: ' . json_last_error_msg();
        }
    }
    
    // Return debug information
    echo json_encode([
        'success' => true,
        'message' => 'Debug information collected',
        'debug_info' => $debug_info,
        'file_checks' => $file_checks,
        'include_status' => $include_errors,
        'database_status' => $db_status,
        'email_functions' => $email_functions_status,
        'request_status' => $request_status,
        'request_data' => $request_data,
        'raw_input' => $_SERVER['REQUEST_METHOD'] === 'POST' ? file_get_contents('php://input') : null
    ], JSON_PRETTY_PRINT);
    
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'message' => 'Debug script error',
        'error' => $e->getMessage(),
        'trace' => $e->getTraceAsString()
    ], JSON_PRETTY_PRINT);
} catch (Error $e) {
    echo json_encode([
        'success' => false,
        'message' => 'PHP Fatal Error',
        'error' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine()
    ], JSON_PRETTY_PRINT);
}
?>