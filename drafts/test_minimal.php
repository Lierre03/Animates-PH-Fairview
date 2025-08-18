<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header('Content-Type: application/json');

try {
    // Check if we can even get to this point
    echo json_encode([
        'success' => true,
        'message' => 'PHP file is accessible',
        'php_version' => phpversion(),
        'functions_exist' => [
            'getDB' => function_exists('getDB'),
            'getStatusFromTapCount' => function_exists('getStatusFromTapCount'),
            'sendBookingStatusEmail' => function_exists('sendBookingStatusEmail')
        ],
        'request_method' => $_SERVER['REQUEST_METHOD'],
        'input' => file_get_contents('php://input')
    ]);
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
        'file' => $e->getFile(),
        'line' => $e->getLine()
    ]);
}
?>