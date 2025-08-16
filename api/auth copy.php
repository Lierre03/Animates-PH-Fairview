<?php
// Always return JSON
header('Content-Type: application/json');

// Handle all PHP errors and exceptions as JSON
set_error_handler(function($errno, $errstr, $errfile, $errline) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => "PHP Error: $errstr in $errfile on line $errline"
    ]);
    exit;
});
set_exception_handler(function($e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => "Uncaught Exception: " . $e->getMessage()
    ]);
    exit;
});

require_once '../config/database.php';
require_once '../vendor/autoload.php'; // For PHPMailer

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\SMTP;
use PHPMailer\PHPMailer\Exception;

$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $action = $input['action'] ?? '';

    if ($action === 'signup') {
        // Example signup logic — keep your existing implementation here
        // Just make sure to end with echo json_encode([...]);

        $firstName = $input['firstName'] ?? '';
        $lastName = $input['lastName'] ?? '';
        $email = $input['email'] ?? '';
        $phone = $input['phone'] ?? '';
        $password = $input['password'] ?? '';
        $marketingEmails = $input['marketingEmails'] ?? false;

        // TODO: Your existing DB insert and email sending logic here
        // Example response:
        echo json_encode([
            'success' => true,
            'verification_token' => 'sample_token_123'
        ]);
        exit;

    } elseif ($action === 'login') {
        // Example login logic
        echo json_encode([
            'success' => true,
            'token' => 'sample_auth_token',
            'user_id' => 1
        ]);
        exit;

    } elseif ($action === 'verify_email') {
        // Example verification
        echo json_encode([
            'success' => true,
            'token' => 'sample_auth_token',
            'user_id' => 1
        ]);
        exit;

    } elseif ($action === 'forgot_password') {
        echo json_encode([
            'success' => true
        ]);
        exit;

    } elseif ($action === 'resend_verification') {
        echo json_encode([
            'success' => true
        ]);
        exit;

    } elseif ($action === 'verify_token') {
        echo json_encode([
            'success' => true
        ]);
        exit;

    } else {
        echo json_encode([
            'success' => false,
            'error' => 'Invalid action'
        ]);
        exit;
    }
} else {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'error' => 'Method not allowed'
    ]);
    exit;
}


function handleLogin($input) {
    try {
        $db = getDB();
        
        if (empty($input['email']) || empty($input['password'])) {
            throw new Exception('Email and password are required');
        }
        
        // Get user by email
        $stmt = $db->prepare("SELECT id, password_hash, email_verified, is_active, first_name, last_name FROM users WHERE email = ?");
        $stmt->execute([$input['email']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user || !password_verify($input['password'], $user['password_hash'])) {
            throw new Exception('Invalid email or password');
        }
        
        if (!$user['email_verified']) {
            throw new Exception('Please verify your email before signing in');
        }
        
        if (!$user['is_active']) {
            throw new Exception('Your account has been deactivated. Please contact support');
        }
        
        // Generate JWT token
        $token = generateJWT($user['id'], $user['email']);
        
        // Update last login
        $stmt = $db->prepare("UPDATE users SET last_login = NOW() WHERE id = ?");
        $stmt->execute([$user['id']]);
        
        echo json_encode([
            'success' => true,
            'token' => $token,
            'user_id' => $user['id'],
            'user' => [
                'name' => $user['first_name'] . ' ' . $user['last_name'],
                'email' => $input['email']
            ]
        ]);
        
    } catch(Exception $e) {
        http_response_code(400);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function handleSignup($input) {
    try {
        $db = getDB();
        
        // Validate required fields
        $required = ['firstName', 'lastName', 'email', 'phone', 'password'];
        foreach ($required as $field) {
            if (empty($input[$field])) {
                throw new Exception(ucfirst($field) . ' is required');
            }
        }
        
        // Validate email format
        if (!filter_var($input['email'], FILTER_VALIDATE_EMAIL)) {
            throw new Exception('Invalid email format');
        }
        
        // Validate password strength
        if (strlen($input['password']) < 8) {
            throw new Exception('Password must be at least 8 characters long');
        }
        
        // Check if email already exists
        $stmt = $db->prepare("SELECT id FROM users WHERE email = ?");
        $stmt->execute([$input['email']]);
        if ($stmt->fetch()) {
            throw new Exception('An account with this email already exists');
        }
        
        // Check if phone already exists
        $stmt = $db->prepare("SELECT id FROM users WHERE phone = ?");
        $stmt->execute([$input['phone']]);
        if ($stmt->fetch()) {
            throw new Exception('An account with this phone number already exists');
        }
        
        $db->beginTransaction();
        
        // Create user
        $passwordHash = password_hash($input['password'], PASSWORD_DEFAULT);
        $verificationCode = sprintf('%06d', mt_rand(0, 999999));
        $verificationToken = bin2hex(random_bytes(32));
        
        $stmt = $db->prepare("
            INSERT INTO users (first_name, last_name, email, phone, password_hash, verification_code, verification_token, marketing_emails) 
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ");
        
        $stmt->execute([
            $input['firstName'],
            $input['lastName'],
            $input['email'],
            $input['phone'],
            $passwordHash,
            $verificationCode,
            $verificationToken,
            $input['marketingEmails'] ? 1 : 0
        ]);
        
        $userId = $db->lastInsertId();
        
        // Send verification email
        sendVerificationEmail($input['email'], $input['firstName'], $verificationCode);
        
        $db->commit();
        
        echo json_encode([
            'success' => true,
            'verification_token' => $verificationToken,
            'message' => 'Account created successfully. Please check your email for verification code.'
        ]);
        
    } catch(Exception $e) {
        if ($db->inTransaction()) {
            $db->rollback();
        }
        http_response_code(400);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function handleEmailVerification($input) {
    try {
        $db = getDB();
        
        if (empty($input['verification_token']) || empty($input['verification_code'])) {
            throw new Exception('Verification token and code are required');
        }
        
        // Get user by verification token
        $stmt = $db->prepare("
            SELECT id, email, verification_code, verification_code_expires, first_name, last_name 
            FROM users 
            WHERE verification_token = ? AND email_verified = 0
        ");
        $stmt->execute([$input['verification_token']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) {
            throw new Exception('Invalid verification token or email already verified');
        }
        
        // Check if code has expired (30 minutes)
        if (strtotime($user['verification_code_expires']) < time()) {
            throw new Exception('Verification code has expired. Please request a new one.');
        }
        
        // Check verification code
        if ($user['verification_code'] !== $input['verification_code']) {
            throw new Exception('Invalid verification code');
        }
        
        // Verify the email
        $stmt = $db->prepare("
            UPDATE users 
            SET email_verified = 1, email_verified_at = NOW(), verification_code = NULL, verification_token = NULL 
            WHERE id = ?
        ");
        $stmt->execute([$user['id']]);
        
        // Generate JWT token for auto-login
        $token = generateJWT($user['id'], $user['email']);
        
        echo json_encode([
            'success' => true,
            'token' => $token,
            'user_id' => $user['id'],
            'user' => [
                'name' => $user['first_name'] . ' ' . $user['last_name'],
                'email' => $user['email']
            ],
            'message' => 'Email verified successfully!'
        ]);
        
    } catch(Exception $e) {
        http_response_code(400);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function handleResendVerification($input) {
    try {
        $db = getDB();
        
        if (empty($input['verification_token'])) {
            throw new Exception('Verification token is required');
        }
        
        // Get user by verification token
        $stmt = $db->prepare("
            SELECT id, email, first_name 
            FROM users 
            WHERE verification_token = ? AND email_verified = 0
        ");
        $stmt->execute([$input['verification_token']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) {
            throw new Exception('Invalid verification token or email already verified');
        }
        
        // Generate new verification code
        $verificationCode = sprintf('%06d', mt_rand(0, 999999));
        
        $stmt = $db->prepare("
            UPDATE users 
            SET verification_code = ?, verification_code_expires = DATE_ADD(NOW(), INTERVAL 30 MINUTE) 
            WHERE id = ?
        ");
        $stmt->execute([$verificationCode, $user['id']]);
        
        // Send new verification email
        sendVerificationEmail($user['email'], $user['first_name'], $verificationCode);
        
        echo json_encode([
            'success' => true,
            'message' => 'New verification code sent to your email'
        ]);
        
    } catch(Exception $e) {
        http_response_code(400);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function handleForgotPassword($input) {
    try {
        $db = getDB();
        
        if (empty($input['email'])) {
            throw new Exception('Email is required');
        }
        
        // Check if user exists
        $stmt = $db->prepare("SELECT id, first_name FROM users WHERE email = ? AND email_verified = 1");
        $stmt->execute([$input['email']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) {
            // Don't reveal if email exists or not for security
            echo json_encode([
                'success' => true,
                'message' => 'If an account with this email exists, you will receive reset instructions.'
            ]);
            return;
        }
        
        // Generate reset token
        $resetToken = bin2hex(random_bytes(32));
        $resetExpires = date('Y-m-d H:i:s', strtotime('+1 hour'));
        
        $stmt = $db->prepare("
            UPDATE users 
            SET password_reset_token = ?, password_reset_expires = ? 
            WHERE id = ?
        ");
        $stmt->execute([$resetToken, $resetExpires, $user['id']]);
        
        // Send reset email
        sendPasswordResetEmail($input['email'], $user['first_name'], $resetToken);
        
        echo json_encode([
            'success' => true,
            'message' => 'Password reset instructions sent to your email'
        ]);
        
    } catch(Exception $e) {
        http_response_code(400);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function handleResetPassword($input) {
    try {
        $db = getDB();
        
        if (empty($input['token']) || empty($input['password'])) {
            throw new Exception('Reset token and new password are required');
        }
        
        // Validate password strength
        if (strlen($input['password']) < 8) {
            throw new Exception('Password must be at least 8 characters long');
        }
        
        // Get user by reset token
        $stmt = $db->prepare("
            SELECT id 
            FROM users 
            WHERE password_reset_token = ? AND password_reset_expires > NOW()
        ");
        $stmt->execute([$input['token']]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) {
            throw new Exception('Invalid or expired reset token');
        }
        
        // Update password
        $passwordHash = password_hash($input['password'], PASSWORD_DEFAULT);
        $stmt = $db->prepare("
            UPDATE users 
            SET password_hash = ?, password_reset_token = NULL, password_reset_expires = NULL 
            WHERE id = ?
        ");
        $stmt->execute([$passwordHash, $user['id']]);
        
        echo json_encode([
            'success' => true,
            'message' => 'Password reset successfully'
        ]);
        
    } catch(Exception $e) {
        http_response_code(400);
        echo json_encode(['error' => $e->getMessage()]);
    }
}

function verifyToken() {
    try {
        $token = getBearerToken();
        if (!$token) {
            throw new Exception('No token provided');
        }
        
        $decoded = verifyJWT($token);
        
        echo json_encode([
            'success' => true,
            'user_id' => $decoded->user_id,
            'email' => $decoded->email
        ]);
        
    } catch(Exception $e) {
        http_response_code(401);
        echo json_encode(['error' => 'Invalid token']);
    }
}

// JWT Functions
function generateJWT($userId, $email) {
    $header = json_encode(['typ' => 'JWT', 'alg' => 'HS256']);
    $payload = json_encode([
        'user_id' => $userId,
        'email' => $email,
        'iat' => time(),
        'exp' => time() + (30 * 24 * 60 * 60) // 30 days
    ]);
    
    $base64Header = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($header));
    $base64Payload = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($payload));
    
    $signature = hash_hmac('sha256', $base64Header . "." . $base64Payload, getJWTSecret(), true);
    $base64Signature = str_replace(['+', '/', '='], ['-', '_', ''], base64_encode($signature));
    
    return $base64Header . "." . $base64Payload . "." . $base64Signature;
}

function verifyJWT($token) {
    $parts = explode('.', $token);
    if (count($parts) !== 3) {
        throw new Exception('Invalid token format');
    }
    
    $header = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $parts[0])));
    $payload = json_decode(base64_decode(str_replace(['-', '_'], ['+', '/'], $parts[1])));
    $signature = str_replace(['-', '_'], ['+', '/'], $parts[2]);
    
    $expectedSignature = hash_hmac('sha256', $parts[0] . "." . $parts[1], getJWTSecret(), true);
    
    if (!hash_equals($expectedSignature, base64_decode($signature))) {
        throw new Exception('Invalid signature');
    }
    
    if ($payload->exp < time()) {
        throw new Exception('Token expired');
    }
    
    return $payload;
}

function getJWTSecret() {
    // In production, store this in environment variables
    return '8paws_jwt_secret_key_2025';
}

function getBearerToken() {
    $headers = getAuthorizationHeader();
    if (!empty($headers)) {
        if (preg_match('/Bearer\s(\S+)/', $headers, $matches)) {
            return $matches[1];
        }
    }
    return null;
}

function getAuthorizationHeader() {
    $headers = null;
    if (isset($_SERVER['Authorization'])) {
        $headers = trim($_SERVER["Authorization"]);
    } else if (isset($_SERVER['HTTP_AUTHORIZATION'])) {
        $headers = trim($_SERVER["HTTP_AUTHORIZATION"]);
    } elseif (function_exists('apache_request_headers')) {
        $requestHeaders = apache_request_headers();
        $requestHeaders = array_combine(array_map('ucwords', array_keys($requestHeaders)), array_values($requestHeaders));
        if (isset($requestHeaders['Authorization'])) {
            $headers = trim($requestHeaders['Authorization']);
        }
    }
    return $headers;
}

// Email Functions
function sendVerificationEmail($email, $firstName, $verificationCode) {
    $mail = new PHPMailer(true);
    
    try {
        // Server settings
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com'; // Configure with your SMTP settings
        $mail->SMTPAuth   = true;
        $mail->Username   = '8pawspetboutique@gmail.com';
    $mail->Password   = 'ofvcexgxpmmzoond';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        // Recipients
        $mail->setFrom('8pawspetboutique@gmail.com', '8Paws Pet Boutique');
        $mail->addTo($email, $firstName);
        
        // Content
        $mail->isHTML(true);
        $mail->Subject = 'Verify Your Email - 8Paws Pet Boutique';
        $mail->Body = getVerificationEmailTemplate($firstName, $verificationCode);
        
        $mail->send();
    } catch (Exception $e) {
        error_log("Email could not be sent. Mailer Error: {$mail->ErrorInfo}");
        throw new Exception('Failed to send verification email');
    }
}

function sendPasswordResetEmail($email, $firstName, $resetToken) {
    $mail = new PHPMailer(true);
    
    try {
        // Server settings (same as above)
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = 'your-email@gmail.com';
        $mail->Password   = 'your-app-password';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        // Recipients
        $mail->setFrom('noreply@8pawspetboutique.com', '8Paws Pet Boutique');
        $mail->addTo($email, $firstName);
        
        // Content
        $mail->isHTML(true);
        $mail->Subject = 'Reset Your Password - 8Paws Pet Boutique';
        $mail->Body = getPasswordResetEmailTemplate($firstName, $resetToken);
        
        $mail->send();
    } catch (Exception $e) {
        error_log("Email could not be sent. Mailer Error: {$mail->ErrorInfo}");
        throw new Exception('Failed to send password reset email');
    }
}

function getVerificationEmailTemplate($firstName, $verificationCode) {
    return "
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Email Verification</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
            .content { background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .code-box { background: #f8f9fa; border: 2px dashed #667eea; padding: 20px; text-align: center; margin: 20px 0; border-radius: 8px; }
            .code { font-size: 32px; font-weight: bold; color: #667eea; font-family: monospace; letter-spacing: 8px; }
            .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; }
            .button { display: inline-block; background: #667eea; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; margin: 10px 0; }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='header'>
                <h1>🐾 Welcome to 8Paws Pet Boutique!</h1>
                <p>Professional Pet Grooming & Care Services</p>
            </div>
            <div class='content'>
                <h2>Hi $firstName!</h2>
                <p>Thank you for creating your account with 8Paws Pet Boutique. To complete your registration and start booking appointments for your furry friends, please verify your email address.</p>
                
                <div class='code-box'>
                    <p style='margin: 0 0 10px 0; font-weight: bold;'>Your Verification Code:</p>
                    <div class='code'>$verificationCode</div>
                </div>
                
                <p>Enter this code on the verification page to activate your account. This code will expire in 30 minutes.</p>
                
                <p>Once verified, you'll be able to:</p>
                <ul>
                    <li>📅 Book grooming appointments online</li>
                    <li>📱 Track your pet's grooming progress in real-time</li>
                    <li>📋 View service history and receipts</li>
                    <li>🔔 Receive SMS updates and reminders</li>
                </ul>
                
                <p>If you didn't create this account, you can safely ignore this email.</p>
                
                <p>Welcome to the 8Paws family!</p>
                
                <p>Best regards,<br>
                The 8Paws Pet Boutique Team</p>
            </div>
            <div class='footer'>
                <p>8Paws Pet Boutique & Grooming Salon<br>
                📍 123 Pet Street, Quezon City | 📞 (02) 8123-4567<br>
                📧 info@8pawspetboutique.com</p>
            </div>
        </div>
    </body>
    </html>
    ";
}

function getPasswordResetEmailTemplate($firstName, $resetToken) {
    $resetUrl = "http://localhost/8paws/reset_password.html?token=" . $resetToken;
    
    return "
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Password Reset</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
            .content { background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .button { display: inline-block; background: #667eea; color: white; padding: 15px 30px; text-decoration: none; border-radius: 8px; margin: 20px 0; font-weight: bold; }
            .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; }
            .warning { background: #fff3cd; border: 1px solid #ffeaa7; color: #856404; padding: 15px; border-radius: 6px; margin: 15px 0; }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='header'>
                <h1>🔑 Password Reset Request</h1>
                <p>8Paws Pet Boutique & Grooming Salon</p>
            </div>
            <div class='content'>
                <h2>Hi $firstName,</h2>
                <p>We received a request to reset the password for your 8Paws Pet Boutique account.</p>
                
                <p>If you requested this password reset, click the button below to set a new password:</p>
                
                <div style='text-align: center;'>
                    <a href='$resetUrl' class='button'>Reset My Password</a>
                </div>
                
                <p>This link will expire in 1 hour for security reasons.</p>
                
                <div class='warning'>
                    <strong>⚠️ Security Notice:</strong><br>
                    If you didn't request this password reset, please ignore this email. Your account remains secure.
                </div>
                
                <p>For security reasons, this link can only be used once. If you need another reset link, please visit our login page and request a new one.</p>
                
                <p>If you're having trouble with the button above, copy and paste this link into your browser:</p>
                <p style='word-break: break-all; color: #667eea;'>$resetUrl</p>
                
                <p>Best regards,<br>
                The 8Paws Pet Boutique Team</p>
            </div>
            <div class='footer'>
                <p>8Paws Pet Boutique & Grooming Salon<br>
                📍 123 Pet Street, Quezon City | 📞 (02) 8123-4567<br>
                📧 info@8pawspetboutique.com</p>
            </div>
        </div>
    </body>
    </html>
    ";
}
?>