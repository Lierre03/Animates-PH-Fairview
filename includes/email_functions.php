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
                p.name as pet_name,
                p.type as pet_type,
                p.breed as pet_breed,
                p.age_range as pet_age,
                c.name as owner_name,
                c.phone as owner_phone,
                c.email as owner_email,
                r.tap_count,
                su.status,
                GROUP_CONCAT(s.name SEPARATOR ', ') as services
            FROM bookings b
            JOIN pets p ON b.pet_id = p.id
            JOIN customers c ON p.customer_id = c.id
            JOIN rfid_cards r ON b.rfid_tag_id = r.id
            LEFT JOIN status_updates su ON b.id = su.booking_id
            LEFT JOIN booking_services bs ON b.id = bs.booking_id
            LEFT JOIN services s ON bs.service_id = s.id
            WHERE b.id = ?
            ORDER BY su.created_at DESC
            LIMIT 1
        ");
        $stmt->execute([$bookingId]);
        $booking = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$booking || !$booking['owner_email']) {
            throw new Exception('Booking not found or no email address');
        }
        
        // Determine status based on tap_count
        $status = getStatusFromTapCount($booking['tap_count']);
        
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
                        <div class='progress-fill' style='width: " . ($booking['tap_count'] * 25) . "%;'></div>
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
?>