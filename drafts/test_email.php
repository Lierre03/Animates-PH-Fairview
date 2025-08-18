<?php
// test_email.php - Place this in your /api/ folder for testing email functionality
require_once '../config/database.php';
require_once '../includes/email_functions.php';

// Move use statements to the top, outside of any try-catch blocks
use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

// Enable error reporting for debugging
error_reporting(E_ALL);
ini_set('display_errors', 1);

echo "<h1>8Paws Email Configuration Test</h1>";

// Test 1: Check if required files exist
echo "<h2>1. File Existence Check</h2>";
if (file_exists('../vendor/autoload.php')) {
    echo "✅ PHPMailer autoload.php exists<br>";
} else {
    echo "❌ PHPMailer autoload.php NOT found. Run 'composer install' first.<br>";
}

if (file_exists('../includes/email_functions.php')) {
    echo "✅ email_functions.php exists<br>";
} else {
    echo "❌ email_functions.php NOT found<br>";
}

// Test 2: Check PHPMailer classes
echo "<h2>2. PHPMailer Class Check</h2>";
try {
    require_once '../vendor/autoload.php';
    
    $mail = new PHPMailer(true);
    echo "✅ PHPMailer class loaded successfully<br>";
} catch (Exception $e) {
    echo "❌ PHPMailer error: " . $e->getMessage() . "<br>";
}

// Test 3: SMTP Connection Test
echo "<h2>3. SMTP Connection Test</h2>";
try {
    if (function_exists('testEmailConfig')) {
        $result = testEmailConfig();
        if ($result) {
            echo "✅ SMTP connection successful<br>";
        } else {
            echo "❌ SMTP connection failed<br>";
        }
    } else {
        echo "❌ testEmailConfig() function not found in email_functions.php<br>";
        echo "ℹ️ Make sure to add the testEmailConfig() function to your email_functions.php file<br>";
    }
} catch (Exception $e) {
    echo "❌ SMTP test error: " . $e->getMessage() . "<br>";
}

// Test 4: Database Connection Test
echo "<h2>4. Database Connection Test</h2>";
try {
    $db = getDB();
    echo "✅ Database connection successful<br>";
    
    // Check if we have any test bookings
    $stmt = $db->prepare("SELECT COUNT(*) as count FROM bookings");
    $stmt->execute();
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    echo "📊 Total bookings in database: " . $result['count'] . "<br>";
    
} catch (Exception $e) {
    echo "❌ Database error: " . $e->getMessage() . "<br>";
}

// Test 5: Send a test email (if booking ID provided)
if (isset($_GET['booking_id']) && !empty($_GET['booking_id'])) {
    $bookingId = (int)$_GET['booking_id'];
    echo "<h2>5. Test Email Send (Booking ID: $bookingId)</h2>";
    
    try {
        $result = sendBookingStatusEmail($bookingId);
        if ($result) {
            echo "✅ Test email sent successfully!<br>";
        } else {
            echo "❌ Test email failed to send<br>";
        }
    } catch (Exception $e) {
        echo "❌ Email send error: " . $e->getMessage() . "<br>";
    }
} else {
    echo "<h2>5. Test Email Send</h2>";
    echo "ℹ️ To test email sending, add ?booking_id=X to URL (where X is a valid booking ID)<br>";
    echo "Example: test_email.php?booking_id=1<br>";
}

// Test 6: Check email configuration
echo "<h2>6. Email Configuration Check</h2>";
echo "📧 SMTP Host: smtp.gmail.com<br>";
echo "📧 SMTP Port: 587<br>";
echo "📧 From Email: 8pawspetboutique@gmail.com<br>";
echo "⚠️ Make sure to enable 2-factor authentication on Gmail and use an App Password<br>";

// Test 7: Recent bookings for testing
echo "<h2>7. Recent Bookings (for testing)</h2>";
try {
    $db = getDB();
    $stmt = $db->prepare("
        SELECT 
            b.id,
            b.custom_rfid,
            p.name as pet_name,
            c.name as owner_name,
            c.email as owner_email,
            b.created_at
        FROM bookings b
        JOIN pets p ON b.pet_id = p.id
        JOIN customers c ON p.customer_id = c.id
        ORDER BY b.created_at DESC
        LIMIT 5
    ");
    $stmt->execute();
    $bookings = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    if (count($bookings) > 0) {
        echo "<table border='1' cellpadding='5'>";
        echo "<tr><th>Booking ID</th><th>Pet Name</th><th>Owner</th><th>Email</th><th>RFID</th><th>Test Email</th></tr>";
        foreach ($bookings as $booking) {
            echo "<tr>";
            echo "<td>" . $booking['id'] . "</td>";
            echo "<td>" . $booking['pet_name'] . "</td>";
            echo "<td>" . $booking['owner_name'] . "</td>";
            echo "<td>" . $booking['owner_email'] . "</td>";
            echo "<td>" . $booking['custom_rfid'] . "</td>";
            echo "<td><a href='?booking_id=" . $booking['id'] . "'>Send Test Email</a></td>";
            echo "</tr>";
        }
        echo "</table>";
    } else {
        echo "No bookings found in database<br>";
    }
} catch (Exception $e) {
    echo "❌ Error fetching bookings: " . $e->getMessage() . "<br>";
}

echo "<hr>";
echo "<h2>Troubleshooting Tips</h2>";
echo "<ul>";
echo "<li>Make sure Composer is installed and run 'composer require phpmailer/phpmailer'</li>";
echo "<li>Check that Gmail account has 2-factor authentication enabled</li>";
echo "<li>Use an App Password instead of your regular Gmail password</li>";
echo "<li>Check your server's PHP error logs</li>";
echo "<li>Make sure your server can make outbound connections on port 587</li>";
echo "<li>Test with a simple email first before complex booking emails</li>";
echo "</ul>";

?>