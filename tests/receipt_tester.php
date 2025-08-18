<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>8Paws Compact Receipt Tester</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        h1 {
            color: #667eea;
            text-align: center;
            margin-bottom: 30px;
        }
        .test-button {
            display: block;
            width: 100%;
            padding: 15px;
            margin: 10px 0;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 8px;
            font-size: 16px;
            cursor: pointer;
            transition: background 0.3s;
        }
        .test-button:hover {
            background: #5a67d8;
        }
        .test-info {
            background: #e2e8f0;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            font-size: 14px;
        }
        .data-preview {
            background: #f7fafc;
            padding: 15px;
            border-left: 4px solid #667eea;
            margin: 20px 0;
            font-family: monospace;
            font-size: 12px;
            overflow-x: auto;
        }
        .format-info {
            background: #fed7d7;
            color: #742a2a;
            padding: 15px;
            border-radius: 8px;
            margin: 20px 0;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧾 8Paws COMPACT Receipt Tester</h1>
        
        <div class="format-info">
            📏 <strong>NEW FORMAT:</strong> Adaptive receipt size (80mm width) - like thermal receipt printers!
        </div>
        
        <div class="test-info">
            <strong>Test Data Preview:</strong>
            <div class="data-preview">
                <strong>Pet:</strong> tanggol (dog, african, young, small)<br>
                <strong>Owner:</strong> Bryant Iverson C. Melliza<br>
                <strong>Contact:</strong> 0943-135-9316 | bryantiversonmelliza03@gmail.com<br>
                <strong>Booking ID:</strong> #47<br>
                <strong>RFID:</strong> TBAXNIWH<br>
                <strong>Services:</strong> 6 services, Total: PHP 1,800.00
            </div>
        </div>

        <button class="test-button" onclick="generateTestReceipt()">
            🧾 Generate Compact Receipt (6 services)
        </button>

        <button class="test-button" onclick="generateMaxServicesTest()">
            📋 Test Maximum Services (8 services)
        </button>

        <button class="test-button" onclick="generateMinimalTest()">
            📝 Test Minimal Data (1 service)
        </button>

        <div class="test-info">
            <strong>✨ FIXED FEATURES:</strong><br>
            • Full-width centered header<br>
            • Adaptive receipt height<br>
            • Fixed footer visibility<br>
            • All content guaranteed visible<br>
            • Perfect for receipt printers
        </div>
    </div>

    <script>
        // Test data matching your exact content
        const testData = {
            bookingId: 47,
            petData: {
                petName: 'tanggol',
                petType: 'dog',
                petBreed: 'african',
                petAge: 'young',
                petSize: 'small',
                ownerName: 'Bryant Iverson C. Melliza',
                ownerPhone: '0943-135-9316',
                ownerEmail: 'bryantiversonmelliza03@gmail.com',
                rfidTag: 'TBAXNIWH',
                specialNotes: ''
            },
            selectedServices: [
                { name: 'Basic Bath', price: 300.00 },
                { name: 'Nail Trimming', price: 150.00 },
                { name: 'Full Grooming Package', price: 600.00 },
                { name: 'Dental Care', price: 250.00 },
                { name: 'De-shedding Treatment', price: 400.00 },
                { name: 'Nail Polish', price: 100.00 }
            ],
            totalAmount: 1800.00
        };

        const maxServicesData = {
            bookingId: 48,
            petData: {
                petName: 'Max',
                petType: 'dog',
                petBreed: 'golden retriever',
                petAge: 'adult',
                petSize: 'large',
                ownerName: 'John Doe',
                ownerPhone: '0912-345-6789',
                ownerEmail: 'john.doe@email.com',
                rfidTag: 'MAXTEST1',
                specialNotes: 'Very energetic dog'
            },
            selectedServices: [
                { name: 'Basic Bath', price: 300.00 },
                { name: 'Nail Trimming', price: 150.00 },
                { name: 'Ear Cleaning', price: 200.00 },
                { name: 'Full Grooming Package', price: 600.00 },
                { name: 'Dental Care', price: 250.00 },
                { name: 'De-shedding Treatment', price: 400.00 },
                { name: 'Nail Polish', price: 100.00 },
                { name: 'Perfume & Bow', price: 150.00 }
            ],
            totalAmount: 2150.00
        };

        const minimalData = {
            bookingId: 49,
            petData: {
                petName: 'Fluffy',
                petType: 'cat',
                petBreed: 'persian',
                petAge: '',
                petSize: '',
                ownerName: 'Jane Smith',
                ownerPhone: '0923-456-7890',
                ownerEmail: 'jane@email.com',
                rfidTag: 'MINIMAL1',
                specialNotes: ''
            },
            selectedServices: [
                { name: 'Basic Bath', price: 300.00 }
            ],
            totalAmount: 300.00
        };

        function generateTestReceipt() {
            const { bookingId, petData, selectedServices, totalAmount } = testData;
            generateCompactReceipt(bookingId, petData, selectedServices, totalAmount);
        }

        function generateMaxServicesTest() {
            const { bookingId, petData, selectedServices, totalAmount } = maxServicesData;
            generateCompactReceipt(bookingId, petData, selectedServices, totalAmount);
        }

        function generateMinimalTest() {
            const { bookingId, petData, selectedServices, totalAmount } = minimalData;
            generateCompactReceipt(bookingId, petData, selectedServices, totalAmount);
        }

        function generateCompactReceipt(bookingId, petData, selectedServices, totalAmount) {
   const { jsPDF } = window.jspdf;
   
   // More accurate height calculation
   let estimatedHeight = 35; // Header
   estimatedHeight += 25; // Receipt title, date, separator
   estimatedHeight += 15; // Booking details
   estimatedHeight += 15; // Pet info (base)
   estimatedHeight += (petData.petAge || petData.petSize ? 3 : 0); // Extra pet details
   estimatedHeight += 12; // Owner info
   estimatedHeight += 10; // Services header and separators
   estimatedHeight += selectedServices.length * 3; // Each service
   estimatedHeight += 15; // Subtotal and total sections
   estimatedHeight += (petData.specialNotes && petData.specialNotes.trim() ? 12 : 0); // Special notes
   estimatedHeight += 8; // Footer with minimal spacing
   
   // Minimal padding to reduce excess space
   const finalHeight = Math.max(estimatedHeight -25);
   
   // ADAPTIVE RECEIPT SIZE - 80mm width, calculated height
   const doc = new jsPDF({
       unit: 'mm',
       format: [80, finalHeight]
   });
   
   let yPos = 5;
   
   // Header - Full width with proper centering
   doc.setFillColor(102, 126, 234);
   doc.rect(0, 0, 80, 22, 'F'); // Slightly taller header
   
   doc.setTextColor(255, 255, 255);
   doc.setFontSize(10);
   doc.setFont('helvetica', 'bold');
   doc.text('8PAWS PET', 40, 6, { align: 'center' });
   doc.text('BOUTIQUE & GROOMING SALON', 40, 10, { align: 'center' });
   
   doc.setFontSize(7);
   doc.setFont('helvetica', 'normal');
   doc.text('123 Pet Street, Quezon City', 40, 15, { align: 'center' });
   doc.text('(02) 8123-4567', 40, 19, { align: 'center' });
   
   yPos = 27;
   
   // Receipt title
   doc.setTextColor(0, 0, 0);
   doc.setFontSize(8);
   doc.setFont('helvetica', 'bold');
   doc.text('BOOKING RECEIPT', 40, yPos, { align: 'center' });
   yPos += 5;
   
   // Date
   const currentDate = new Date();
   const dateStr = currentDate.toLocaleDateString('en-PH', { 
       year: 'numeric', 
       month: 'short', 
       day: 'numeric' 
   });
   const timeStr = currentDate.toLocaleTimeString('en-PH', { 
       hour: '2-digit', 
       minute: '2-digit',
       hour12: true
   });
   
   doc.setFontSize(6);
   doc.setFont('helvetica', 'normal');
   doc.text(`${dateStr} ${timeStr}`, 40, yPos, { align: 'center' });
   yPos += 5;
   
   // Separator line
   doc.setDrawColor(200, 200, 200);
   doc.line(5, yPos, 75, yPos);
   yPos += 3;
   
   // Booking Details - Single line
   doc.setFontSize(6);
   doc.setFont('helvetica', 'bold');
   doc.text('BOOKING DETAILS', 5, yPos);
   yPos += 3;
   doc.setFont('helvetica', 'normal');
   doc.text(`ID: #${bookingId} | RFID: ${petData.rfidTag}`, 5, yPos);
   yPos += 5;
   
   // Pet Info - Compact
   doc.setFont('helvetica', 'bold');
   doc.text('PET INFO', 5, yPos);
   yPos += 3;
   doc.setFont('helvetica', 'normal');
   doc.text(`${petData.petName} (${petData.petType})`, 5, yPos);
   yPos += 3;
   doc.text(`${petData.petBreed}`, 5, yPos);
   if (petData.petAge || petData.petSize) {
       yPos += 3;
       let details = '';
       if (petData.petAge) details += petData.petAge;
       if (petData.petSize) details += (details ? ', ' : '') + petData.petSize;
       doc.text(details, 5, yPos);
   }
   yPos += 5;
   
   // Owner Info - Compact
   doc.setFont('helvetica', 'bold');
   doc.text('OWNER', 5, yPos);
   yPos += 3;
   doc.setFont('helvetica', 'normal');
   doc.text(petData.ownerName, 5, yPos);
   yPos += 3;
   doc.text(petData.ownerPhone, 5, yPos);
   yPos += 5;
   
   // Separator line
   doc.line(5, yPos, 75, yPos);
   yPos += 3;
   
   // Services Header
   doc.setFont('helvetica', 'bold');
   doc.text('SERVICES', 5, yPos);
   yPos += 4;
   
   // Services List - Very compact
   doc.setFontSize(6);
   doc.setFont('helvetica', 'normal');
   selectedServices.forEach((service, index) => {
       // Service name (truncate if too long)
       let serviceName = service.name;
       if (serviceName.length > 20) {
           serviceName = serviceName.substring(0, 20) + '...';
       }
       doc.text(serviceName, 5, yPos);
       doc.text(`PHP ${service.price.toFixed(2)}`, 75, yPos, { align: 'right' });
       yPos += 3;
   });
   
   yPos += 2;
   
   // Separator line
   doc.line(5, yPos, 75, yPos);
   yPos += 3;
   
   // Subtotal
   doc.setFont('helvetica', 'bold');
   doc.text('SUBTOTAL', 5, yPos);
   doc.text(`PHP ${totalAmount.toFixed(2)}`, 75, yPos, { align: 'right' });
   yPos += 4;
   
   // Total - Highlighted
   doc.setFillColor(102, 126, 234);
   doc.rect(5, yPos - 2, 70, 6, 'F');
   doc.setTextColor(255, 255, 255);
   doc.setFontSize(7);
   doc.setFont('helvetica', 'bold');
   doc.text('TOTAL', 7, yPos + 1);
   doc.text(`PHP ${totalAmount.toFixed(2)}`, 73, yPos + 1, { align: 'right' });
   yPos += 8;
   
   // Special Notes (if any)
   if (petData.specialNotes && petData.specialNotes.trim()) {
       doc.setTextColor(0, 0, 0);
       doc.setFontSize(6);
       doc.setFont('helvetica', 'bold');
       doc.text('NOTES:', 5, yPos);
       yPos += 3;
       doc.setFont('helvetica', 'normal');
       const notes = doc.splitTextToSize(petData.specialNotes, 70);
       doc.text(notes, 5, yPos);
       yPos += notes.length * 3 + 3;
   }
   
   // Minimal space before footer
   yPos += 3;
   
   // Footer - Compact spacing
   doc.setDrawColor(200, 200, 200);
   doc.line(5, yPos, 75, yPos);
   yPos += 5;
   
   // Ensure footer text is black and visible
   doc.setTextColor(0, 0, 0);
   doc.setFontSize(7);
   doc.setFont('helvetica', 'bold');
   doc.text('Thank you for choosing 8Paws!', 40, yPos, { align: 'center' });
   yPos += 3;
   doc.setFont('helvetica', 'normal');
   doc.text('Your pet is in good hands', 40, yPos, { align: 'center' });
   
   // Save PDF
   const cleanPetName = (petData.petName || 'Pet').replace(/[^a-zA-Z0-9]/g, '');
   const fileName = `8Paws_CompactReceipt_${cleanPetName}_${currentDate.toISOString().slice(0, 10)}.pdf`;
   doc.save(fileName);
}
    </script>
</body>
</html>