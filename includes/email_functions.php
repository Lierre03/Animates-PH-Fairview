<?php
require_once '../vendor/autoload.php'; // For PHPMailer

use PHPMailer\PHPMailer\PHPMailer;
use PHPMailer\PHPMailer\Exception;

/**
 * Test SMTP configuration without sending an actual email
 */
function testEmailConfig() {
    try {
        $mail = new PHPMailer(true);
        
        // Server settings (same as your existing configuration)
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = '8pawspetboutique@gmail.com';
        $mail->Password   = 'ofvcexgxpmmzoond';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        // Test SMTP connection
        $mail->SMTPDebug = 0; // Disable debug output for clean test
        
        // Just test the connection without sending
        if ($mail->smtpConnect()) {
            $mail->smtpClose();
            return true;
        } else {
            return false;
        }
        
    } catch (Exception $e) {
        error_log("SMTP Test Error: " . $e->getMessage());
        return false;
    }
}

/**
 * Send booking confirmation email when customer checks in
 */
function sendBookingConfirmationEmail($bookingId) {
    try {
        // Test SMTP configuration first (optional but recommended)
        if (!testEmailConfig()) {
            error_log("SMTP configuration test failed - proceeding anyway");
        }
        
        $db = getDB();
        
        // Get booking details with all required information
        $stmt = $db->prepare("
            SELECT 
                b.id as booking_id,
                b.custom_rfid,
                b.total_amount,
                p.name as pet_name,
                p.type as pet_type,
                p.breed as pet_breed,
                p.age_range as pet_age,
                c.name as owner_name,
                c.phone as owner_phone,
                c.email as owner_email,
                GROUP_CONCAT(s.name SEPARATOR ', ') as services
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            LEFT JOIN booking_services bs ON b.id = bs.booking_id
            LEFT JOIN services s ON bs.service_id = s.id
            WHERE b.id = ?
            GROUP BY b.id
        ");
        $stmt->execute([$bookingId]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking) {
            error_log("Booking not found for ID: $bookingId");
            return false;
        }
        
        if (!$booking['owner_email']) {
            error_log("No email address found for booking ID: $bookingId");
            return false;
        }
        
        // Send email
        $mail = new PHPMailer(true);
        
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = '8pawspetboutique@gmail.com';
        $mail->Password   = 'ofvcexgxpmmzoond';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        $mail->setFrom('8pawspetboutique@gmail.com', '8Paws Pet Boutique');
        $mail->addAddress($booking['owner_email'], $booking['owner_name']);
        
        $mail->isHTML(true);
        $mail->Subject = "Check-in Confirmation - {$booking['pet_name']} at 8Paws Pet Boutique";
        $mail->Body = getBookingConfirmationEmailTemplate($booking);
        
        $mail->send();
        error_log("Booking confirmation email sent successfully to: " . $booking['owner_email']);
        return true;
        
    } catch (Exception $e) {
        error_log("Email could not be sent. Mailer Error: {$e->getMessage()}");
        return false;
    }
}

/**
 * Send booking status update email when RFID tap occurs
 */
function sendBookingStatusEmailFromRFID($bookingId, $tapCount) {
    try {
        $db = getDB();
        
        // Get booking details with all required information
        $stmt = $db->prepare("
            SELECT 
                b.id as booking_id,
                b.custom_rfid,
                b.total_amount,
                b.status,
                p.name as pet_name,
                p.type as pet_type,
                p.breed as pet_breed,
                p.age_range as pet_age,
                c.name as owner_name,
                c.phone as owner_phone,
                c.email as owner_email,
                GROUP_CONCAT(s.name SEPARATOR ', ') as services
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            LEFT JOIN booking_services bs ON b.id = bs.booking_id
            LEFT JOIN services s ON bs.service_id = s.id
            WHERE b.id = ?
            GROUP BY b.id
        ");
        $stmt->execute([$bookingId]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking || !$booking['owner_email']) {
            error_log("Booking not found or no email address for booking ID: $bookingId");
            return false;
        }
        
        // Get status from current booking status (already updated)
        $status = $booking['status'];
        
        // Send email
        $mail = new PHPMailer(true);
        
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = '8pawspetboutique@gmail.com';
        $mail->Password   = 'ofvcexgxpmmzoond';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        $mail->setFrom('8pawspetboutique@gmail.com', '8Paws Pet Boutique');
        $mail->addAddress($booking['owner_email'], $booking['owner_name']);
        
        $mail->isHTML(true);
        $mail->Subject = "Pet Grooming Update - {$booking['pet_name']} is " . ucfirst($status);
        $mail->Body = getBookingStatusEmailTemplateRFID($booking, $status, $tapCount);
        
        $mail->send();
        error_log("RFID status update email sent successfully to: " . $booking['owner_email'] . " for status: $status");
        return true;
        
    } catch (Exception $e) {
        error_log("RFID status email could not be sent. Mailer Error: {$e->getMessage()}");
        return false;
    }
}


/**
 * Send booking status update email
 */
function sendBookingStatusEmail($bookingId) {
    try {
        $db = getDB();
        
        // Get booking details with all required information
        $stmt = $db->prepare("
    SELECT 
        b.id as booking_id,
        b.custom_rfid,
        b.total_amount,
        b.status as current_status,
        p.name as pet_name,
        p.type as pet_type,
        p.breed as pet_breed,
        p.age_range as pet_age,
        c.name as owner_name,
        c.phone as owner_phone,
        c.email as owner_email,
        GROUP_CONCAT(DISTINCT s.name SEPARATOR ', ') as services
    FROM bookings b
    JOIN pets p ON b.pet_id = p.id
    JOIN customers c ON p.customer_id = c.id
    LEFT JOIN booking_services bs ON b.id = bs.booking_id
    LEFT JOIN services s ON bs.service_id = s.id
    WHERE b.id = ?
    GROUP BY b.id
");

        $stmt->execute([$bookingId]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking || !$booking['owner_email']) {
            throw new Exception('Booking not found or no email address');
        }
        
       // Use current booking status instead of calculating from tap count
$status = $booking['current_status'];
        
        // Send email
        $mail = new PHPMailer(true);
        
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = '8pawspetboutique@gmail.com';
        $mail->Password   = 'ofvcexgxpmmzoond';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        $mail->setFrom('8pawspetboutique@gmail.com', '8Paws Pet Boutique');
        $mail->addAddress($booking['owner_email'], $booking['owner_name']);
        
        $mail->isHTML(true);
        $mail->Subject = "Pet Grooming Update - {$booking['pet_name']} is {$status}";
        $mail->Body = getBookingStatusEmailTemplate($booking, $status);
        
        $mail->send();
        return true;
        
    } catch (Exception $e) {
        error_log("Email could not be sent. Mailer Error: {$e->getMessage()}");
        return false;
    }
}

/**
 * Get status based on tap count
 */
function getStatusFromTapCount($tapCount) {
    switch($tapCount) {
        case 1: return 'checked-in';
        case 2: return 'bathing';
        case 3: return 'grooming';
        case 4: return 'ready for pickup';
        default: return 'unknown';
    }
}

/**
 * Email template for booking confirmation
 */
function getBookingConfirmationEmailTemplate($booking) {
    return "
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Check-in Confirmation</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
            .content { background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
            .info-item { background: #f8f9fa; padding: 15px; border-radius: 8px; }
            .info-label { font-size: 12px; color: #666; text-transform: uppercase; font-weight: bold; margin-bottom: 5px; }
            .info-value { font-size: 16px; color: #333; font-weight: 500; }
            .services-list { background: #f1f5f9; padding: 15px; border-radius: 8px; margin: 15px 0; }
            .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; }
            
            @media only screen and (max-width: 600px) {
                .info-grid { grid-template-columns: 1fr; gap: 10px; }
            }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='header'>
                <div style='font-size: 48px; margin-bottom: 10px;'>✅</div>
                <h1 style='margin: 0; font-size: 28px;'>Check-in Confirmed!</h1>
                <p style='margin: 15px 0 0 0; opacity: 0.9;'>Welcome to 8Paws Pet Boutique</p>
            </div>
            
            <div class='content'>
                <p style='font-size: 18px; margin-bottom: 25px;'>Hello {$booking['owner_name']},</p>
                
                <p>Thank you for choosing 8Paws Pet Boutique! We've successfully checked in {$booking['pet_name']} and assigned an RFID tag for easy tracking.</p>
                
                <div class='info-grid'>
                    <div class='info-item'>
                        <div class='info-label'>Pet Information</div>
                        <div class='info-value'>{$booking['pet_name']}</div>
                        <div style='font-size: 14px; color: #666;'>{$booking['pet_type']} • {$booking['pet_breed']}" . ($booking['pet_age'] ? " • " . ucfirst($booking['pet_age']) : "") . "</div>
                    </div>
                    <div class='info-item'>
                        <div class='info-label'>Owner Contact</div>
                        <div class='info-value'>{$booking['owner_name']}</div>
                        <div style='font-size: 14px; color: #666;'>{$booking['owner_phone']}</div>
                    </div>
                </div>
                
                " . ($booking['services'] ? "
                <div class='services-list'>
                    <div class='info-label'>Services Selected</div>
                    <div class='info-value'>{$booking['services']}</div>
                    <div style='font-size: 14px; color: #666; margin-top: 5px;'>Total: ₱" . number_format($booking['total_amount'], 2) . "</div>
                </div>
                " : "") . "
                
                <div style='background: #eff6ff; padding: 20px; border-radius: 8px; margin: 20px 0;'>
                    <div class='info-label'>RFID Tag Assigned</div>
                    <div style='font-family: monospace; font-size: 20px; font-weight: bold; color: #1d4ed8; margin: 5px 0;'>{$booking['custom_rfid']}</div>
                    <div style='font-size: 14px; color: #666;'>Use this ID to track your pet's progress</div>
                </div>
                
                <div style='background: #dcfce7; border: 1px solid #16a34a; padding: 20px; border-radius: 10px; margin: 20px 0;'>
                    <h3 style='color: #16a34a; margin: 0 0 10px 0;'>What's Next?</h3>
                    <p style='margin: 0; color: #15803d;'>We'll send you email updates as {$booking['pet_name']} progresses through each grooming stage. Estimated completion time is 1-2 hours.</p>
                </div>
                
                <p style='margin-top: 30px;'>Thank you for trusting us with {$booking['pet_name']}'s care!</p>
                
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

/**
 * Email template for booking status updates
 */
function getBookingStatusEmailTemplate($booking, $status) {
    $statusEmoji = [
        'checked-in' => '✅',
        'bathing' => '🛁',
        'grooming' => '✂️',
        'ready for pickup' => '🎉'
    ];
    
    $statusColors = [
        'checked-in' => '#3B82F6',
        'bathing' => '#06B6D4',
        'grooming' => '#8B5CF6',
        'ready for pickup' => '#10B981'
    ];
    
    $currentEmoji = $statusEmoji[$status] ?? '📋';
    $currentColor = $statusColors[$status] ?? '#667eea';
    
    return "
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Pet Grooming Update</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, {$currentColor} 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
            .content { background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .status-badge { background: {$currentColor}; color: white; padding: 8px 16px; border-radius: 20px; display: inline-block; font-weight: bold; margin: 10px 0; }
            .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
            .info-item { background: #f8f9fa; padding: 15px; border-radius: 8px; }
            .info-label { font-size: 12px; color: #666; text-transform: uppercase; font-weight: bold; margin-bottom: 5px; }
            .info-value { font-size: 16px; color: #333; font-weight: 500; }
            .progress-bar { background: #e5e7eb; height: 8px; border-radius: 4px; margin: 20px 0; overflow: hidden; }
            .progress-fill { background: {$currentColor}; height: 100%; border-radius: 4px; transition: width 0.3s ease; }
            .progress-labels { 
                display: table; 
                width: 100%; 
                table-layout: fixed;
                font-size: 12px; 
                color: #666; 
                margin-top: 8px;
            }
            .progress-label { 
                display: table-cell; 
                text-align: center;
                padding: 0 5px;
            }
            .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; }
            .services-list { background: #f1f5f9; padding: 15px; border-radius: 8px; margin: 15px 0; }
            
            @media only screen and (max-width: 600px) {
                .info-grid { grid-template-columns: 1fr; gap: 10px; }
                .progress-labels { font-size: 10px; }
                .progress-label { padding: 0 2px; }
            }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='header'>
                <div style='font-size: 48px; margin-bottom: 10px;'>{$currentEmoji}</div>
                <h1 style='margin: 0; font-size: 28px;'>{$booking['pet_name']} Update</h1>
                <div class='status-badge' style='background: rgba(255,255,255,0.2); margin-top: 15px;'>
                    Status: " . ucfirst($status) . "
                </div>
            </div>
            
            <div class='content'>
                <p style='font-size: 18px; margin-bottom: 25px;'>Hello {$booking['owner_name']},</p>
                
                <p>We wanted to update you on {$booking['pet_name']}'s grooming progress at 8Paws Pet Boutique!</p>
                
                <div class='info-grid'>
                    <div class='info-item'>
                        <div class='info-label'>Pet Information</div>
                        <div class='info-value'>{$booking['pet_name']}</div>
                        <div style='font-size: 14px; color: #666;'>{$booking['pet_type']} • {$booking['pet_breed']}" . ($booking['pet_age'] ? " • " . ucfirst($booking['pet_age']) : "") . "</div>
                    </div>
                    <div class='info-item'>
                        <div class='info-label'>Owner Contact</div>
                        <div class='info-value'>{$booking['owner_name']}</div>
                        <div style='font-size: 14px; color: #666;'>{$booking['owner_phone']}</div>
                    </div>
                </div>
                
                " . ($booking['services'] ? "
                <div class='services-list'>
                    <div class='info-label'>Services Selected</div>
                    <div class='info-value'>{$booking['services']}</div>
                    <div style='font-size: 14px; color: #666; margin-top: 5px;'>Total: ₱" . number_format($booking['total_amount'], 2) . "</div>
                </div>
                " : "") . "
                
                <div style='background: #eff6ff; padding: 20px; border-radius: 8px; margin: 20px 0;'>
                    <div class='info-label'>RFID Tag Assigned</div>
                    <div style='font-family: monospace; font-size: 20px; font-weight: bold; color: #1d4ed8; margin: 5px 0;'>{$booking['custom_rfid']}</div>
                    <div style='font-size: 14px; color: #666;'>Current Status: <strong>" . ucfirst($status) . "</strong></div>
                </div>
                
                <div style='margin: 25px 0;'>
                    <div style='font-size: 16px; font-weight: bold; margin-bottom: 10px;'>Grooming Progress</div>
                    <div class='progress-bar'>
                       <div class='progress-fill' style='width: " . getProgressPercentage($status) . "%;'></div>
                    </div>
                    <div class='progress-labels'>
                        <div class='progress-label'>Check-in</div>
                        <div class='progress-label'>Bathing</div>
                        <div class='progress-label'>Grooming</div>
                        <div class='progress-label'>Ready</div>
                    </div>
                </div>
                
                " . ($status === 'ready for pickup' ? "
                <div style='background: #dcfce7; border: 2px solid #16a34a; padding: 20px; border-radius: 10px; text-align: center; margin: 20px 0;'>
                    <h3 style='color: #16a34a; margin: 0 0 10px 0;'>🎉 Ready for Pickup!</h3>
                    <p style='margin: 0; color: #15803d;'>Your pet is all groomed and ready to go home! Please come by at your earliest convenience.</p>
                </div>
                " : "
                <p>We'll send you another update when {$booking['pet_name']} moves to the next stage. Thank you for choosing 8Paws Pet Boutique!</p>
                ") . "
                
                <p style='margin-top: 30px;'>Best regards,<br>
                The 8Paws Pet Boutique Team</p>
            </div>
            
            <div class='footer'>
                <p>8Paws Pet Boutique & Grooming Salon<br>
                📍 123 Pet Street, Quezon City | 📞 (02) 8123-4567<br>
                📧 info@8pawspetboutique.com</p>
                <p style='margin-top: 15px; font-size: 12px; color: #999;'>
                    This email was sent because you have an active booking with us. 
                    Your RFID tag: {$booking['custom_rfid']}
                </p>
            </div>
        </div>
    </body>
    </html>
    ";
}

/**
 * Email template for RFID-triggered status updates
 */
function getBookingStatusEmailTemplateRFID($booking, $status, $tapCount) {
    $statusEmoji = [
        'checked-in' => '✅',
        'bathing' => '🛁',
        'grooming' => '✂️',
        'ready' => '🎉'
    ];
    
    $statusColors = [
        'checked-in' => '#3B82F6',
        'bathing' => '#06B6D4',
        'grooming' => '#8B5CF6',
        'ready' => '#10B981'
    ];
    
    $statusDescriptions = [
        'checked-in' => 'Your pet has been checked in and is waiting for services',
        'bathing' => 'Your pet is currently being bathed and pampered',
        'grooming' => 'Professional grooming services in progress',
        'ready' => 'Your pet is ready! Please come for pickup'
    ];
    
    $currentEmoji = $statusEmoji[$status] ?? '📋';
    $currentColor = $statusColors[$status] ?? '#667eea';
    $currentDescription = $statusDescriptions[$status] ?? 'Status updated';
    
    return "
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Real-time Pet Update</title>
        <style>
            body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .header { background: linear-gradient(135deg, {$currentColor} 0%, #764ba2 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
            .content { background: white; padding: 30px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .status-badge { background: {$currentColor}; color: white; padding: 8px 16px; border-radius: 20px; display: inline-block; font-weight: bold; margin: 10px 0; }
            .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0; }
            .info-item { background: #f8f9fa; padding: 15px; border-radius: 8px; }
            .info-label { font-size: 12px; color: #666; text-transform: uppercase; font-weight: bold; margin-bottom: 5px; }
            .info-value { font-size: 16px; color: #333; font-weight: 500; }
            .progress-bar { background: #e5e7eb; height: 8px; border-radius: 4px; margin: 20px 0; overflow: hidden; }
            .progress-fill { background: {$currentColor}; height: 100%; border-radius: 4px; transition: width 0.3s ease; }
            .footer { text-align: center; padding: 20px; color: #666; font-size: 14px; }
            .services-list { background: #f1f5f9; padding: 15px; border-radius: 8px; margin: 15px 0; }
            .realtime-badge { background: #ff6b6b; color: white; padding: 4px 8px; border-radius: 12px; font-size: 11px; font-weight: bold; display: inline-block; margin-bottom: 10px; }
            
            @media only screen and (max-width: 600px) {
                .info-grid { grid-template-columns: 1fr; gap: 10px; }
            }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='header'>
                <div class='realtime-badge'>🔄 REAL-TIME UPDATE</div>
                <div style='font-size: 48px; margin-bottom: 10px;'>{$currentEmoji}</div>
                <h1 style='margin: 0; font-size: 28px;'>{$booking['pet_name']} Update</h1>
                <div class='status-badge' style='background: rgba(255,255,255,0.2); margin-top: 15px;'>
                    Status: " . ucfirst($status) . "
                </div>
            </div>
            
            <div class='content'>
                <p style='font-size: 18px; margin-bottom: 25px;'>Hello {$booking['owner_name']},</p>
                
                <div style='background: #e8f4fd; border-left: 4px solid {$currentColor}; padding: 15px; margin: 20px 0; border-radius: 0 8px 8px 0;'>
                    <strong>📍 Live Update:</strong> {$currentDescription}
                </div>
                
                <div class='info-grid'>
                    <div class='info-item'>
                        <div class='info-label'>Pet Information</div>
                        <div class='info-value'>{$booking['pet_name']}</div>
                        <div style='font-size: 14px; color: #666;'>{$booking['pet_type']} • {$booking['pet_breed']}" . ($booking['pet_age'] ? " • " . ucfirst($booking['pet_age']) : "") . "</div>
                    </div>
                    <div class='info-item'>
                        <div class='info-label'>RFID Tracking</div>
                        <div style='font-family: monospace; font-size: 16px; font-weight: bold; color: #1d4ed8;'>{$booking['custom_rfid']}</div>
                        <div style='font-size: 12px; color: #666;'>Tap #{$tapCount} • " . date('g:i A') . "</div>
                    </div>
                </div>
                
                " . ($booking['services'] ? "
                <div class='services-list'>
                    <div class='info-label'>Services Selected</div>
                    <div class='info-value'>{$booking['services']}</div>
                    <div style='font-size: 14px; color: #666; margin-top: 5px;'>Total: ₱" . number_format($booking['total_amount'], 2) . "</div>
                </div>
                " : "") . "
                
                <div style='margin: 25px 0;'>
                    <div style='font-size: 16px; font-weight: bold; margin-bottom: 10px;'>🚀 Grooming Progress</div>
                    <div class='progress-bar'>
                        <div class='progress-fill' style='width: " . ($tapCount * 25) . "%;'></div>
                    </div>
                    <div style='display: flex; justify-content: space-between; font-size: 12px; color: #666; margin-top: 8px;'>
                        <span>Check-in</span>
                        <span>Bathing</span>
                        <span>Grooming</span>
                        <span>Ready</span>
                    </div>
                </div>
                
                " . ($status === 'ready' ? "
                <div style='background: #dcfce7; border: 2px solid #16a34a; padding: 20px; border-radius: 10px; text-align: center; margin: 20px 0;'>
                    <h3 style='color: #16a34a; margin: 0 0 10px 0;'>🎉 Ready for Pickup!</h3>
                    <p style='margin: 0; color: #15803d;'>Your pet is all groomed and ready to go home! Please come by at your earliest convenience.</p>
                </div>
                " : "
                <p>We'll send you another real-time update when {$booking['pet_name']} moves to the next stage. You can also track live progress through your dashboard!</p>
                ") . "
                
                <p style='margin-top: 30px;'>Best regards,<br>
                The 8Paws Pet Boutique Team</p>
            </div>
            
            <div class='footer'>
                <p>8Paws Pet Boutique & Grooming Salon<br>
                📍 123 Pet Street, Quezon City | 📞 (02) 8123-4567<br>
                📧 8pawspetboutique@gmail.com</p>
                <p style='margin-top: 15px; font-size: 12px; color: #999;'>
                    This is a real-time update from our RFID tracking system.<br>
                    Booking RFID: {$booking['custom_rfid']} • Update #{$tapCount}
                </p>
            </div>
        </div>
    </body>
    </html>
    ";
}

/**
 * Get progress percentage based on status
 */
function getProgressPercentage($status) {
    $progressMap = [
        'checked-in' => 25,
        'bathing' => 50,
        'grooming' => 75,
        'ready' => 100,
        'completed' => 100
    ];
    
    return $progressMap[$status] ?? 0;
}


/**
 * Send completion/pickup email when service is finished (tap 5)
 * Add this function to your email_functions.php file
 */
function sendCompletionEmail($bookingId) {
    try {
        $db = getDB();
        
        // Get booking details with all required information
        $stmt = $db->prepare("
            SELECT 
                b.id as booking_id,
                b.custom_rfid,
                b.total_amount,
                b.status,
                b.check_in_time,
                b.actual_completion,
                p.name as pet_name,
                p.type as pet_type,
                p.breed as pet_breed,
                p.age_range as pet_age,
                c.name as owner_name,
                c.phone as owner_phone,
                c.email as owner_email,
                GROUP_CONCAT(DISTINCT s.name SEPARATOR ', ') as services
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            LEFT JOIN booking_services bs ON b.id = bs.booking_id
            LEFT JOIN services s ON bs.service_id = s.id
            WHERE b.id = ?
            GROUP BY b.id
        ");
        $stmt->execute([$bookingId]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking || !$booking['owner_email']) {
            throw new Exception('Booking not found or no email address');
        }
        
        // Send email
        $mail = new PHPMailer(true);
        
        $mail->isSMTP();
        $mail->Host       = 'smtp.gmail.com';
        $mail->SMTPAuth   = true;
        $mail->Username   = '8pawspetboutique@gmail.com';
        $mail->Password   = 'ofvcexgxpmmzoond';
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = 587;
        
        $mail->setFrom('8pawspetboutique@gmail.com', '8Paws Pet Boutique');
        $mail->addAddress($booking['owner_email'], $booking['owner_name']);
        
        $mail->isHTML(true);
        $mail->Subject = "Thank You! {$booking['pet_name']}'s Service Completed ✨";
        $mail->Body = getCompletionEmailTemplate($booking);
        
        $mail->send();
        error_log("Completion email sent successfully to: " . $booking['owner_email']);
        return true;
        
    } catch (Exception $e) {
        error_log("Completion email could not be sent. Mailer Error: {$e->getMessage()}");
        return false;
    }
}

/**
 * Creative completion email template
 */
function getCompletionEmailTemplate($booking) {
    // Calculate total service time
    $checkInTime = new DateTime($booking['check_in_time']);
    $completionTime = new DateTime($booking['actual_completion']);
    $serviceTime = $checkInTime->diff($completionTime);
    
    $timeSpent = '';
    if ($serviceTime->h > 0) {
        $timeSpent = $serviceTime->h . 'h ' . $serviceTime->i . 'm';
    } else {
        $timeSpent = $serviceTime->i . ' minutes';
    }
    
    return "
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset='UTF-8'>
        <meta name='viewport' content='width=device-width, initial-scale=1.0'>
        <title>Service Completed - Thank You!</title>
        <style>
            body { font-family: 'Segoe UI', Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
            .container { max-width: 600px; margin: 0 auto; padding: 20px; }
            .card { background: white; border-radius: 20px; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.1); }
            .header { 
                background: linear-gradient(135deg, #10B981 0%, #059669 100%); 
                color: white; 
                padding: 40px 30px; 
                text-align: center; 
                position: relative;
                overflow: hidden;
            }
            .header::before {
                content: '';
                position: absolute;
                top: -50%;
                left: -50%;
                width: 200%;
                height: 200%;
                background: radial-gradient(circle, rgba(255,255,255,0.1) 0%, transparent 70%);
                animation: sparkle 3s ease-in-out infinite;
            }
            @keyframes sparkle {
                0%, 100% { transform: rotate(0deg) scale(1); opacity: 0.3; }
                50% { transform: rotate(180deg) scale(1.1); opacity: 0.7; }
            }
            .content { padding: 40px 30px; }
            .celebration-banner {
                background: linear-gradient(45deg, #FFD700, #FFA500);
                margin: -40px -30px 30px -30px;
                padding: 20px;
                text-align: center;
                color: #8B4513;
                font-weight: bold;
                font-size: 18px;
                position: relative;
            }
            .celebration-banner::after {
                content: '🎊 ✨ 🎊 ✨ 🎊 ✨ 🎊';
                position: absolute;
                top: -10px;
                left: 0;
                right: 0;
                font-size: 12px;
                animation: float 2s ease-in-out infinite;
            }
            @keyframes float {
                0%, 100% { transform: translateY(0px); }
                50% { transform: translateY(-5px); }
            }
            .info-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 30px 0; }
            .info-item { 
                background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%); 
                padding: 20px; 
                border-radius: 12px; 
                border-left: 4px solid #10B981;
                transition: transform 0.2s ease;
            }
            .info-item:hover { transform: translateY(-2px); }
            .info-label { font-size: 12px; color: #666; text-transform: uppercase; font-weight: bold; margin-bottom: 8px; }
            .info-value { font-size: 18px; color: #1a202c; font-weight: 600; }
            .services-showcase { 
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
                color: white; 
                padding: 25px; 
                border-radius: 15px; 
                margin: 25px 0; 
                text-align: center;
            }
            .rating-section {
                background: #fef7e6;
                border: 2px dashed #f59e0b;
                padding: 25px;
                border-radius: 15px;
                text-align: center;
                margin: 25px 0;
            }
            .rating-stars {
                font-size: 32px;
                margin: 15px 0;
                cursor: pointer;
            }
            .footer { 
                background: linear-gradient(135deg, #1f2937 0%, #374151 100%); 
                color: white; 
                padding: 30px; 
                text-align: center; 
                border-radius: 0 0 20px 20px;
            }
            .social-links {
                margin-top: 20px;
            }
            .social-links a {
                display: inline-block;
                margin: 0 10px;
                color: #60a5fa;
                text-decoration: none;
                font-size: 24px;
                transition: transform 0.2s ease;
            }
            .social-links a:hover { transform: scale(1.2); }
            .completion-badge {
                display: inline-block;
                background: #10B981;
                color: white;
                padding: 8px 20px;
                border-radius: 25px;
                font-size: 14px;
                font-weight: bold;
                margin: 15px 0;
                box-shadow: 0 4px 15px rgba(16, 185, 129, 0.3);
            }
            
            @media only screen and (max-width: 600px) {
                .info-grid { grid-template-columns: 1fr; gap: 15px; }
                .container { padding: 10px; }
                .content { padding: 30px 20px; }
                .celebration-banner { margin: -40px -20px 30px -20px; }
            }
        </style>
    </head>
    <body>
        <div class='container'>
            <div class='card'>
                <div class='header'>
                    <div style='font-size: 64px; margin-bottom: 15px; position: relative; z-index: 1;'>🎉</div>
                    <h1 style='margin: 0; font-size: 32px; position: relative; z-index: 1;'>Mission Accomplished!</h1>
                    <p style='margin: 15px 0 0 0; opacity: 0.9; font-size: 18px; position: relative; z-index: 1;'>{$booking['pet_name']} is looking fabulous!</p>
                    <div class='completion-badge'>✨ SERVICE COMPLETED ✨</div>
                </div>
                
                <div class='content'>
                    <div class='celebration-banner'>
                        🏆 Another Happy Pet, Another Satisfied Family! 🏆
                    </div>
                    
                    <p style='font-size: 20px; margin-bottom: 25px; color: #10B981; font-weight: 600;'>Dear {$booking['owner_name']},</p>
                    
                    <p style='font-size: 16px; line-height: 1.8;'>
                        We're thrilled to let you know that <strong>{$booking['pet_name']}</strong> has successfully completed their pampering session at 8Paws Pet Boutique! 
                        Your furry family member has been groomed to perfection and is ready to strut their stuff! ✨
                    </p>
                    
                    <div class='info-grid'>
                        <div class='info-item'>
                            <div class='info-label'>📅 Service Summary</div>
                            <div class='info-value'>{$booking['pet_name']}</div>
                            <div style='font-size: 14px; color: #666; margin-top: 5px;'>
                                {$booking['pet_type']} • {$booking['pet_breed']}<br>
                                Service Time: {$timeSpent}
                            </div>
                        </div>
                        <div class='info-item'>
                            <div class='info-label'>🏷️ Tracking Details</div>
                            <div style='font-family: monospace; font-size: 16px; font-weight: bold; color: #1d4ed8; margin-bottom: 5px;'>{$booking['custom_rfid']}</div>
                            <div style='font-size: 14px; color: #666;'>
                                Completed: " . date('M j, Y g:i A', strtotime($booking['actual_completion'])) . "
                            </div>
                        </div>
                    </div>
                    
                    " . ($booking['services'] ? "
                    <div class='services-showcase'>
                        <h3 style='margin: 0 0 15px 0; font-size: 20px;'>✨ Services Completed ✨</h3>
                        <div style='font-size: 18px; font-weight: 600;'>{$booking['services']}</div>
                        <div style='font-size: 24px; margin-top: 15px; font-weight: bold;'>Total: ₱" . number_format($booking['total_amount'], 2) . "</div>
                    </div>
                    " : "") . "
                    
                    <div style='background: linear-gradient(135deg, #ecfdf5 0%, #d1fae5 100%); border: 2px solid #10B981; padding: 25px; border-radius: 15px; margin: 25px 0; text-align: center;'>
                        <h3 style='color: #065f46; margin: 0 0 15px 0; font-size: 22px;'>🌟 Thank You for Choosing 8Paws! 🌟</h3>
                        <p style='margin: 0; color: #047857; font-size: 16px; line-height: 1.6;'>
                            Your trust in our services means everything to us. We hope {$booking['pet_name']} enjoyed their spa day as much as we enjoyed pampering them! 
                            We look forward to seeing you both again soon. 💕
                        </p>
                    </div>
                    
                    <div class='rating-section'>
                        <h3 style='color: #92400e; margin: 0 0 10px 0;'>🌟 How did we do? 🌟</h3>
                        <p style='color: #78350f; margin: 10px 0;'>We'd love to hear about your experience!</p>
                        <div class='rating-stars'>⭐⭐⭐⭐⭐</div>
                        <p style='font-size: 14px; color: #a16207; margin: 10px 0 0 0;'>
                            Visit our Facebook page or Google Reviews to share your feedback!
                        </p>
                    </div>
                    
                    <div style='background: #fef3c7; border: 1px solid #fbbf24; padding: 20px; border-radius: 10px; margin: 25px 0; text-align: center;'>
                        <h4 style='color: #92400e; margin: 0 0 10px 0;'>💡 Pet Care Tips</h4>
                        <p style='font-size: 14px; color: #78350f; margin: 0; line-height: 1.6;'>
                            To maintain {$booking['pet_name']}'s fresh look: Brush regularly, keep ears clean, and book your next grooming session in 4-6 weeks!
                        </p>
                    </div>
                    
                    <p style='margin-top: 40px; font-size: 18px; text-align: center;'>
                        With love and gratitude,<br>
                        <strong style='color: #10B981;'>The 8Paws Pet Boutique Family</strong> 🐾
                    </p>
                </div>
                
                <div class='footer'>
                    <h3 style='margin: 0 0 15px 0; color: #60a5fa;'>Stay Connected!</h3>
                    <p style='margin: 15px 0;'>
                        8Paws Pet Boutique & Grooming Salon<br>
                        📍 123 Pet Street, Quezon City<br>
                        📞 (02) 8123-4567 | 📧 8pawspetboutique@gmail.com
                    </p>
                    
                    <div class='social-links'>
                        <a href='#' title='Facebook'>📘</a>
                        <a href='#' title='Instagram'>📷</a>
                        <a href='#' title='Google Reviews'>⭐</a>
                        <a href='#' title='Website'>🌐</a>
                    </div>
                    
                    <p style='margin-top: 20px; font-size: 12px; color: #9ca3af; opacity: 0.8;'>
                        This email confirms that {$booking['pet_name']}'s service has been completed.<br>
                        Booking ID: {$booking['booking_id']} | RFID: {$booking['custom_rfid']}
                    </p>
                </div>
            </div>
        </div>
    </body>
    </html>
    ";
}

?>