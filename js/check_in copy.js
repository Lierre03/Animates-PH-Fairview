let currentStep = 1;
let selectedServices = [];
let totalAmount = 0;
let petData = {};
let bookingId = null;
let rfidPollingInterval = null;
let rfidAssigned = false;

// API base URL - adjust this to your server location
const API_BASE = 'http://localhost/8paws/api/';

// Step navigation
function nextStep() {
    if (currentStep === 1) {
        if (validatePetInfo()) {
            goToStep(2);
        }
    } else if (currentStep === 2) {
        if (selectedServices.length > 0) {
            goToStep(3);
            startRFIDAssignment();
        }
    }
}

function previousStep() {
    if (currentStep === 3) {
        stopRFIDPolling();
    }
    goToStep(currentStep - 1);
}

function goToStep(step) {
    // Hide all steps
    document.querySelectorAll('.form-step').forEach(el => el.classList.add('hidden'));
    
    // Show current step
    if (step === 'success') {
        document.getElementById('success-message').classList.remove('hidden');
    } else {
        document.getElementById(`form-step-${step}`).classList.remove('hidden');
        updateProgress(step);
        currentStep = step;
    }
}

function updateProgress(step) {
    // Reset all steps
    for (let i = 1; i <= 3; i++) {
        const stepEl = document.getElementById(`step${i}`);
        const textEl = document.getElementById(`step${i}-text`);
        const progressEl = document.getElementById(`progress${i}`);
        
        if (i < step) {
            stepEl.className = 'w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm font-medium';
            stepEl.innerHTML = '✓';
            textEl.className = 'ml-2 text-sm font-medium text-green-600';
            if (progressEl) progressEl.className = 'w-16 h-0.5 bg-green-500';
        } else if (i === step) {
            stepEl.className = 'w-8 h-8 bg-primary rounded-full flex items-center justify-center text-white text-sm font-medium';
            stepEl.innerHTML = i;
            textEl.className = 'ml-2 text-sm font-medium text-gray-900';
        } else {
            stepEl.className = 'w-8 h-8 bg-gray-300 rounded-full flex items-center justify-center text-gray-500 text-sm font-medium';
            stepEl.innerHTML = i;
            textEl.className = 'ml-2 text-sm font-medium text-gray-500';
            if (progressEl) progressEl.className = 'w-16 h-0.5 bg-gray-300';
        }
    }
}

// Validate pet information
function validatePetInfo() {
    const required = ['petName', 'petType', 'ownerName', 'ownerPhone', 'ownerEmail'];
    let isValid = true;
    
    required.forEach(field => {
        const input = document.getElementById(field);
        if (!input.value.trim()) {
            input.classList.add('border-red-500');
            isValid = false;
        } else {
            input.classList.remove('border-red-500');
            petData[field] = input.value.trim();
        }
    });

    // Handle custom pet type for "others"
    const petType = document.getElementById('petType').value;
    if (petType === 'others') {
        const customPetType = document.getElementById('customPetType');
        if (!customPetType.value.trim()) {
            customPetType.classList.add('border-red-500');
            isValid = false;
        } else {
            customPetType.classList.remove('border-red-500');
            petData.petType = customPetType.value.trim();
        }
    }

    // Validate pet breed
    let breedValue = '';
    
    if (petType === 'others') {
        const customBreed = document.getElementById('petBreedCustom');
        if (!customBreed.value.trim()) {
            customBreed.classList.add('border-red-500');
            isValid = false;
        } else {
            customBreed.classList.remove('border-red-500');
            breedValue = customBreed.value.trim();
        }
    } else {
        const breedSelect = document.getElementById('petBreed');
        if (!breedSelect.value) {
            breedSelect.classList.add('border-red-500');
            isValid = false;
        } else {
            breedSelect.classList.remove('border-red-500');
            breedValue = breedSelect.value;
        }
    }
    
    if (breedValue) {
        petData.petBreed = breedValue;
    }

    // Store optional fields
    petData.petAge = document.getElementById('petAge').value;
    petData.petSize = document.getElementById('petSize').value;
    petData.specialNotes = document.getElementById('specialNotes').value;
    
    return isValid;
}

// Pet type change handler
document.addEventListener('DOMContentLoaded', function() {
    const petTypeSelect = document.getElementById('petType');
    const petBreedSelect = document.getElementById('petBreed');
    const petBreedCustom = document.getElementById('petBreedCustom');
    
    petTypeSelect.addEventListener('change', async function() {
        const petType = this.value;
        const customPetTypeContainer = document.getElementById('customPetTypeContainer');
        const customPetTypeInput = document.getElementById('customPetType');
        
        if (petType === 'others') {
            customPetTypeContainer.classList.remove('hidden');
            customPetTypeInput.required = true;
            
            petBreedSelect.classList.add('hidden');
            petBreedCustom.classList.remove('hidden');
            petBreedSelect.disabled = true;
            petBreedCustom.required = true;
            petBreedSelect.required = false;
        } else {
            customPetTypeContainer.classList.add('hidden');
            customPetTypeInput.required = false;
            customPetTypeInput.value = '';
            
            if (petType) {
                petBreedSelect.classList.remove('hidden');
                petBreedCustom.classList.add('hidden');
                petBreedSelect.disabled = false;
                petBreedCustom.required = false;
                petBreedSelect.required = true;
                
                await loadBreeds(petType);
            } else {
                petBreedSelect.classList.remove('hidden');
                petBreedCustom.classList.add('hidden');
                petBreedSelect.disabled = true;
                petBreedCustom.required = false;
                petBreedSelect.required = false;
                petBreedSelect.innerHTML = '<option value="">First select pet type</option>';
            }
        }
    });

    // Initialize service selection listeners
    const checkboxes = document.querySelectorAll('.service-checkbox');
    checkboxes.forEach(checkbox => {
        checkbox.addEventListener('change', updateServiceSelection);
    });
});

// Load breeds from API
async function loadBreeds(petType) {
    const petBreedSelect = document.getElementById('petBreed');
    
    try {
        petBreedSelect.innerHTML = '<option value="">Loading breeds...</option>';
        
        let apiUrl = '';
        if (petType === 'dog') {
            apiUrl = 'https://dog.ceo/api/breeds/list/all';
        } else if (petType === 'cat') {
            apiUrl = 'https://api.thecatapi.com/v1/breeds';
        }
        
        const response = await fetch(apiUrl);
        const data = await response.json();
        
        petBreedSelect.innerHTML = '<option value="">Select breed</option>';
        
        if (petType === 'dog') {
            const breeds = Object.keys(data.message);
            breeds.forEach(breed => {
                const option = document.createElement('option');
                option.value = breed;
                option.textContent = breed.charAt(0).toUpperCase() + breed.slice(1);
                petBreedSelect.appendChild(option);
            });
        } else if (petType === 'cat') {
            data.forEach(breed => {
                const option = document.createElement('option');
                option.value = breed.name;
                option.textContent = breed.name;
                petBreedSelect.appendChild(option);
            });
        }
        
    } catch (error) {
        console.error('Error loading breeds:', error);
        petBreedSelect.innerHTML = '<option value="">Error loading breeds - please select "Others" and enter manually</option>';
        showNotification('Could not load breed list. Please select "Others" and enter breed manually.', 'warning');
    }
}

// Handle service selection with decimal support
function updateServiceSelection() {
    selectedServices = [];
    totalAmount = 0;
    
    document.querySelectorAll('.service-checkbox:checked').forEach(checkbox => {
        const service = {
            name: checkbox.dataset.service,
            price: parseFloat(checkbox.dataset.price)
        };
        selectedServices.push(service);
        totalAmount += service.price;
    });
    
    updateOrderSummary();
    
    // Enable/disable next button
    const nextBtn = document.getElementById('servicesNextBtn');
    if (selectedServices.length > 0) {
        nextBtn.disabled = false;
        nextBtn.className = 'bg-primary hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-medium transition-colors';
        nextBtn.textContent = 'Next: RFID Assignment';
    } else {
        nextBtn.disabled = true;
        nextBtn.className = 'bg-gray-300 text-gray-500 px-8 py-3 rounded-lg font-medium cursor-not-allowed';
    }
}

function updateOrderSummary() {
    const servicesContainer = document.getElementById('selectedServices');
    const totalElement = document.getElementById('totalAmount');
    
    if (selectedServices.length === 0) {
        servicesContainer.innerHTML = '<p class="text-gray-500 text-center py-4">No services selected</p>';
    } else {
        servicesContainer.innerHTML = selectedServices.map(service => 
            `<div class="flex justify-between items-center">
                <span>${service.name}</span>
                <span class="font-semibold">₱${service.price.toFixed(2)}</span>
            </div>`
        ).join('');
    }
    
    totalElement.textContent = `₱${totalAmount.toFixed(2)}`;
}

// RFID Assignment and Firebase Integration
function startRFIDAssignment() {
    const rfidStatus = document.getElementById('rfidStatus');
    const rfidMessage = document.getElementById('rfidMessage');
    const assignedTag = document.getElementById('assignedTag');
    
    // Reset RFID state
    rfidAssigned = false;
    
    // Update booking summary
    updateBookingSummary();
    
    // Show initial message
    rfidStatus.textContent = 'Waiting for RFID tap...';
    rfidMessage.textContent = 'Please tap your RFID card on the scanner';
    assignedTag.textContent = '---';
    
    // Disable complete button
    const completeBtn = document.getElementById('completeBtn');
    completeBtn.disabled = true;
    completeBtn.className = 'bg-gray-300 text-gray-500 px-8 py-3 rounded-lg font-medium cursor-not-allowed';
    
    // Start polling for RFID data from Firebase
    startRFIDPolling();
}

function startRFIDPolling() {
    // Stop any existing polling
    stopRFIDPolling();
    
    // Poll every 2 seconds for new RFID data
    rfidPollingInterval = setInterval(async () => {
        try {
            const response = await fetch(API_BASE + 'firebase_sync.php');
            const result = await response.json();
            
            if (result.success && !rfidAssigned) {
                handleRFIDDetection(result);
            }
        } catch (error) {
            console.error('RFID polling error:', error);
        }
    }, 2000);
}

function stopRFIDPolling() {
    if (rfidPollingInterval) {
        clearInterval(rfidPollingInterval);
        rfidPollingInterval = null;
    }
}

function handleRFIDDetection(rfidData) {
    const rfidStatus = document.getElementById('rfidStatus');
    const rfidMessage = document.getElementById('rfidMessage');
    const assignedTag = document.getElementById('assignedTag');
    
    if (rfidData.tapCount === 1) {
        // First tap - assign RFID for check-in
        rfidStatus.textContent = 'RFID Card Detected!';
        rfidMessage.textContent = 'Card assigned successfully';
        assignedTag.textContent = rfidData.customUID;
        
        // Store RFID data
        petData.rfidTag = rfidData.customUID;
        rfidAssigned = true;
        
        // Enable complete button
        const completeBtn = document.getElementById('completeBtn');
        completeBtn.disabled = false;
        completeBtn.className = 'bg-green-600 hover:bg-green-700 text-white px-8 py-3 rounded-lg font-medium transition-colors';
        
        // Stop polling
        stopRFIDPolling();
        
        showNotification('RFID card detected and assigned!', 'success');
        
    } else {
        // Subsequent tap - show status update message
        rfidStatus.textContent = `RFID Tap #${rfidData.tapCount} Detected`;
        rfidMessage.textContent = 'Pet status updated - Tap logged';
        showNotification(`RFID tap #${rfidData.tapCount} logged - Status updated`, 'info');
    }
}

async function completeBooking() {
    if (!rfidAssigned || !petData.rfidTag) {
        showNotification('Please wait for RFID assignment before completing check-in', 'warning');
        return;
    }
    
    try {
        const bookingData = {
            petName: petData.petName,
            petType: petData.petType,
            petBreed: petData.petBreed,
            petAge: petData.petAge,
            petSize: petData.petSize,
            ownerName: petData.ownerName,
            ownerPhone: petData.ownerPhone,
            ownerEmail: petData.ownerEmail,
            specialNotes: petData.specialNotes,
            services: selectedServices,
            totalAmount: parseFloat(totalAmount.toFixed(2)),
            customRFID: petData.rfidTag // Use Firebase RFID
        };

        const response = await fetch(API_BASE + 'check_in.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(bookingData)
        });

        const result = await response.json();

        if (result.success) {
            bookingId = result.booking_id;
            
            // Show success message
            document.getElementById('finalTagId').textContent = petData.rfidTag;
            document.getElementById('finalBookingId').textContent = bookingId;
            goToStep('success');
            
            showNotification('Check-in completed successfully!', 'success');
            
        } else {
            throw new Error(result.error || 'Failed to create booking');
        }
    } catch (error) {
        console.error('Error creating booking:', error);
        showNotification('Error creating booking: ' + error.message, 'error');
    }
}

function updateBookingSummary() {
    document.getElementById('summaryPetName').textContent = petData.petName;
    document.getElementById('summaryPetDetails').textContent = `${petData.petType} - ${petData.petBreed} ${petData.petAge ? `• ${petData.petAge}` : ''} ${petData.petSize ? `• ${petData.petSize}` : ''}`;
    document.getElementById('summaryOwnerName').textContent = petData.ownerName;
    document.getElementById('summaryOwnerContact').textContent = `${petData.ownerPhone} ${petData.ownerEmail ? `• ${petData.ownerEmail}` : ''}`;
    
    const servicesContainer = document.getElementById('summaryServices');
    servicesContainer.innerHTML = selectedServices.map(service => 
        `<div class="flex justify-between items-center text-sm">
            <span>${service.name}</span>
            <span>₱${service.price.toFixed(2)}</span>
        </div>`
    ).join('');
    
    document.getElementById('summaryTotal').textContent = `₱${totalAmount.toFixed(2)}`;
}

function redirectToPortal() {
    // Store RFID tag for portal tracking
    localStorage.setItem('currentRFID', petData.rfidTag);
    window.location.href = 'customer_portal.html';
}

function startNewBooking() {
    // Reset all data
    currentStep = 1;
    selectedServices = [];
    totalAmount = 0;
    petData = {};
    bookingId = null;
    rfidAssigned = false;
    
    // Stop any ongoing RFID polling
    stopRFIDPolling();
    
    // Reset form
    document.getElementById('petInfoForm').reset();
    document.querySelectorAll('.service-checkbox').forEach(cb => cb.checked = false);
    updateOrderSummary();
    
    // Reset breed fields
    document.getElementById('petBreed').innerHTML = '<option value="">First select pet type</option>';
    document.getElementById('petBreed').disabled = true;
    document.getElementById('petBreedCustom').classList.add('hidden');
    document.getElementById('petBreed').classList.remove('hidden');
    
    // Reset custom pet type field
    document.getElementById('customPetTypeContainer').classList.add('hidden');
    document.getElementById('customPetType').value = '';
    
    // Go back to step 1
    goToStep(1);
}

// Notification system
function showNotification(message, type = 'info') {
    const notification = document.createElement('div');
    const colors = {
        success: 'bg-green-500',
        error: 'bg-red-500',
        warning: 'bg-yellow-500',
        info: 'bg-blue-500'
    };
    
    notification.className = `fixed top-4 right-4 ${colors[type]} text-white px-6 py-4 rounded-lg shadow-lg z-50 transform translate-x-full transition-transform duration-300`;
    notification.textContent = message;
    
    document.body.appendChild(notification);
    
    // Animate in
    setTimeout(() => {
        notification.classList.remove('translate-x-full');
    }, 100);
    
    // Remove after 4 seconds
    setTimeout(() => {
        notification.classList.add('translate-x-full');
        setTimeout(() => {
            notification.remove();
        }, 300);
    }, 4000);
}

// Handle form submission for step 1
document.getElementById('petInfoForm').addEventListener('submit', function(e) {
    e.preventDefault();
    nextStep();
});

// Initialize progress
updateProgress(1);

// Phone number formatting
document.getElementById('ownerPhone').addEventListener('input', function(e) {
    let value = e.target.value.replace(/\D/g, '');
    if (value.length > 0) {
        if (value.length <= 4) {
            value = value;
        } else if (value.length <= 7) {
            value = value.slice(0, 4) + '-' + value.slice(4);
        } else {
            value = value.slice(0, 4) + '-' + value.slice(4, 7) + '-' + value.slice(7, 11);
        }
    }
    e.target.value = value;
});

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
    stopRFIDPolling();
});