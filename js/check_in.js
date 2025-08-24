let currentStep = 1;
let selectedServices = [];
let totalAmount = 0;
let petData = {};
let bookingId = null;
let rfidPollingInterval = null;
let rfidAssigned = false;
let lastNotifiedError = null; // Track last error to prevent spam
let servicesData = {};
let currentPetSize = '';

// API base URL - adjust this to your server location
const API_BASE = 'http://localhost/animates/api/';


// Add this function near the top of the file with other utility functions
function getPhysicalCardNumber(cardUID) {
    const cardMapping = {
        '73:77:f8:39': 'Card #1',
        'c2:48:94:ab': 'Card #2', 
        '11:7b:b0:01': 'Card #4',
        '4c:3f:b6:01': 'Card #6',
        '53:89:08:02': 'Card #3',
        '69:33:b2:01': 'Card #5'
    };
    
    return cardMapping[cardUID] || `Unknown Card (${cardUID})`;
}


// Load services when page loads
document.addEventListener('DOMContentLoaded', function() {
    loadServicesFromDatabase();
    
    // Add event listener for pet size selection
    const petSizeSelect = document.getElementById('petSizeForPricing');
    petSizeSelect.addEventListener('change', function() {
        currentPetSize = this.value;
        renderServices();
        // Clear selected services when size changes
        selectedServices = [];
        updateOrderSummary();
    });
});

async function loadServicesFromDatabase() {
    try {
        const response = await fetch(API_BASE + 'services.php?action=get_services');
        const result = await response.json();
        
        if (result.success) {
            servicesData = result.services;
            renderServices();
        } else {
            throw new Error(result.error || 'Failed to load services');
        }
    } catch (error) {
        console.error('Error loading services:', error);
        showNotification('Failed to load services. Please refresh the page.', 'error');
        
        // Show error state in services container
        document.getElementById('servicesContainer').innerHTML = `
            <div class="text-center py-8">
                <svg class="w-12 h-12 text-red-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-red-600 font-medium">Failed to load services</p>
                <button onclick="loadServicesFromDatabase()" class="mt-2 px-4 py-2 bg-red-100 text-red-700 rounded-lg hover:bg-red-200">
                    Try Again
                </button>
            </div>
        `;
    }
}

function renderServices() {
    const container = document.getElementById('servicesContainer');
    
    if (!currentPetSize) {
        container.innerHTML = `
            <div class="text-center py-8">
                <svg class="w-12 h-12 text-amber-400 mx-auto mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
                </svg>
                <p class="text-amber-600 font-medium">Please select your pet's size first</p>
                <p class="text-sm text-amber-500">This will show accurate pricing for all services</p>
            </div>
        `;
        return;
    }
    
    let html = '';
    
    // Basic Services
    if (servicesData.basic && servicesData.basic.length > 0) {
        html += renderServiceCategory('basic', 'Basic Services', 'blue', servicesData.basic);
    }
    
    // Premium Services
    if (servicesData.premium && servicesData.premium.length > 0) {
        html += renderServiceCategory('premium', 'Premium Services', 'purple', servicesData.premium);
    }
    
    // Add-ons
    if (servicesData.addon && servicesData.addon.length > 0) {
        html += renderServiceCategory('addon', 'Add-ons', 'green', servicesData.addon);
    }
    
    container.innerHTML = html;
    
    // Re-attach event listeners
    const checkboxes = document.querySelectorAll('.service-checkbox');
    checkboxes.forEach(checkbox => {
        checkbox.addEventListener('change', updateServiceSelection);
    });
}

function renderServiceCategory(categoryKey, categoryTitle, color, services) {
    const colorClasses = {
        blue: {
            gradient: 'from-blue-50 to-indigo-50',
            border: 'border-blue-200',
            iconBg: 'bg-blue-100',
            iconText: 'text-blue-600',
            titleText: 'text-blue-900',
            itemBorder: 'border-blue-200 hover:border-blue-300'
        },
        purple: {
            gradient: 'from-purple-50 to-pink-50',
            border: 'border-purple-200',
            iconBg: 'bg-purple-100',
            iconText: 'text-purple-600',
            titleText: 'text-purple-900',
            itemBorder: 'border-purple-200 hover:border-purple-300'
        },
        green: {
            gradient: 'from-green-50 to-emerald-50',
            border: 'border-green-200',
            iconBg: 'bg-green-100',
            iconText: 'text-green-600',
            titleText: 'text-green-900',
            itemBorder: 'border-green-200 hover:border-green-300'
        }
    };
    
    const colors = colorClasses[color];
    const icons = {
        basic: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z"></path>',
        premium: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 3v4M3 5h4M6 17v4m-2-2h4m5-16l2.286 6.857L21 12l-5.714 2.143L13 21l-2.286-6.857L5 12l5.714-2.143L13 3z"></path>',
        addon: '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v13m0-13V6a2 2 0 112 2h-2zm0 0V5.5A2.5 2.5 0 109.5 8H12z"></path>'
    };
    
    let html = `
        <div class="bg-gradient-to-r ${colors.gradient} border-2 ${colors.border} rounded-xl p-6 shadow-sm">
            <div class="flex items-center mb-4">
                <div class="inline-flex items-center justify-center w-10 h-10 ${colors.iconBg} rounded-full mr-3">
                    <svg class="w-6 h-6 ${colors.iconText}" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        ${icons[categoryKey]}
                    </svg>
                </div>
                <h3 class="text-lg font-semibold ${colors.titleText}">${categoryTitle}</h3>
            </div>
            <div class="space-y-4">
    `;
    
   services.forEach(service => {
    const price = getServicePrice(service);
    let priceDisplay = '';
    let isDisabled = false;
    
    if (service.is_size_based && currentPetSize && price > 0) {
        // Size-based service with selected size - show specific price
        priceDisplay = `₱${price.toFixed(2)}`;
        isDisabled = false;
    } else if (service.is_size_based && !currentPetSize) {
        // Size-based service without selected size - show base price if available
        if (service.base_price && service.base_price > 0) {
            priceDisplay = `From ₱${service.base_price.toFixed(2)}`;
        } else {
            // Find the lowest price from available pricing
            const prices = Object.values(service.pricing || {});
            if (prices.length > 0) {
                const minPrice = Math.min(...prices);
                priceDisplay = `From ₱${minPrice.toFixed(2)}`;
            } else {
                priceDisplay = 'Select pet size first';
            }
        }
        isDisabled = true; // Disable until size is selected
    } else if (!service.is_size_based) {
        // Fixed price service - always show price and enable
        if (price > 0) {
            priceDisplay = `₱${price.toFixed(2)}`;
            isDisabled = false;
        } else if (service.base_price && service.base_price > 0) {
            priceDisplay = `₱${service.base_price.toFixed(2)}`;
            isDisabled = false;
        } else {
            priceDisplay = 'Price not available';
            isDisabled = true;
        }
    } else {
        // Fallback case
        priceDisplay = 'Select pet size first';
        isDisabled = true;
    }
    
    html += `
        <label class="flex items-center p-4 bg-white/80 rounded-lg border ${colors.itemBorder} transition-all duration-200 cursor-pointer hover:shadow-md ${isDisabled ? 'opacity-60' : ''}">
            <input type="checkbox" class="service-checkbox w-5 h-5 text-primary rounded" 
                   data-service-id="${service.id}"
                   data-service="${service.name}" 
                   data-price="${price}"
                   ${isDisabled ? 'disabled' : ''}>
            <div class="ml-4 flex-1 flex justify-between items-center">
                <div>
                    <span class="font-medium text-gray-900">${service.name}</span>
                    <p class="text-sm text-gray-600">${service.description}</p>
                    ${service.is_size_based ? `<p class="text-xs text-gray-500 mt-1">Size-based pricing</p>` : ''}
                    ${isDisabled && service.is_size_based ? `<p class="text-xs text-amber-600 mt-1">Please select pet size above</p>` : ''}
                </div>
                <span class="text-lg font-bold text-primary">${priceDisplay}</span>
            </div>
        </label>
    `;
});
    
    html += `
            </div>
        </div>
    `;
    
    return html;
}


function getServicePrice(service) {
    // For size-based services, return specific size price if available
    if (service.is_size_based && currentPetSize && service.pricing && service.pricing[currentPetSize]) {
        return service.pricing[currentPetSize];
    }
    
    // For non-size-based services, return any available price
    if (!service.is_size_based) {
        // Check if there's a fixed price in pricing object
        if (service.pricing && Object.keys(service.pricing).length > 0) {
            return Object.values(service.pricing)[0]; // Return first available price
        }
        // Fallback to base price
        if (service.base_price && service.base_price > 0) {
            return service.base_price;
        }
    }
    
    // Return 0 if no price available (will trigger "Select pet size first" message)
    return 0;
}




// Step navigation
function nextStep() {
    if (currentStep === 1) {
        if (validatePetInfo()) {
            goToStep(2);
        }
    } else if (currentStep === 2) {
        // Validate pet size selection
        if (!currentPetSize) {
            showNotification('Please select your pet size for pricing', 'warning');
            document.getElementById('petSizeForPricing').focus();
            return;
        }
        
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
        updateProgress('success');
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
        
        if (i < step || (step === 'success' && i <= 2)) {
            stepEl.className = 'w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm font-medium';
            stepEl.innerHTML = '✓';
            textEl.className = 'ml-2 text-sm font-medium text-green-600';
            if (progressEl) progressEl.className = 'w-16 h-0.5 bg-green-500';
        } else if (i === step && step !== 'success') {
            stepEl.className = 'w-8 h-8 bg-primary rounded-full flex items-center justify-center text-white text-sm font-medium';
            stepEl.innerHTML = i;
            textEl.className = 'ml-2 text-sm font-medium text-gray-900';
        } else if (step === 'success' && i === 3) {
            stepEl.className = 'w-8 h-8 bg-green-500 rounded-full flex items-center justify-center text-white text-sm font-medium';
            stepEl.innerHTML = '✓';
            textEl.className = 'ml-2 text-sm font-medium text-green-600';
        } else {
            stepEl.className = 'w-8 h-8 bg-gray-300 rounded-full flex items-center justify-center text-gray-500 text-sm font-medium';
            stepEl.innerHTML = i;
            textEl.className = 'ml-2 text-sm font-medium text-gray-500';
            if (progressEl) progressEl.className = 'w-16 h-0.5 bg-gray-300';
        }
    }
}

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

    // Store optional fields (petAge only, remove petSize)
    petData.petAge = document.getElementById('petAge').value;
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
            id: parseInt(checkbox.dataset.serviceId),
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

// RFID Assignment and MySQL Integration
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
    assignedTag.textContent = '';
    
    // Disable complete button
    const completeBtn = document.getElementById('completeBtn');
    completeBtn.disabled = true;
    completeBtn.className = 'bg-gray-300 text-gray-500 px-8 py-3 rounded-lg font-medium cursor-not-allowed';
    
    // Start polling for RFID data from MySQL
    startRFIDPolling();
}

function startRFIDPolling() {
    // Stop any existing polling
    stopRFIDPolling();
    
    // Reset error tracking
    lastNotifiedError = null;
    
    // Poll every 2 seconds for new RFID data from MySQL
    rfidPollingInterval = setInterval(async () => {
        try {
            const response = await fetch(API_BASE + 'check_in.php?action=get_latest_rfid');
            const result = await response.json();
            
            if (result.success && !rfidAssigned) {
                // Clear any previous error
                lastNotifiedError = null;
                handleRFIDDetection(result);
            } else if (!result.success && result.message) {
                // Only show error notification if it's different from the last one
                if (lastNotifiedError !== result.message) {
                    lastNotifiedError = result.message;
                    // Only show notification for important errors, not repetitive ones
                    if (!result.message.includes('currently in use') && !result.message.includes('No RFID data found')) {
                        showNotification(result.message, 'warning');
                    }
                }
            }
        } catch (error) {
            console.error('RFID polling error:', error);
            // Only show network errors once
            if (lastNotifiedError !== 'network_error') {
                lastNotifiedError = 'network_error';
                showNotification('Connection error. Please check your network.', 'error');
            }
        }
    }, 2000);
}

function stopRFIDPolling() {
    if (rfidPollingInterval) {
        clearInterval(rfidPollingInterval);
        rfidPollingInterval = null;
    }
    // Reset error tracking when stopping
    lastNotifiedError = null;
}

function handleRFIDDetection(rfidData) {
    const rfidStatus = document.getElementById('rfidStatus');
    const rfidMessage = document.getElementById('rfidMessage');
    const assignedTag = document.getElementById('assignedTag');
    const pulseIndicator = document.querySelector('.flex.space-x-1'); // Select the pulse container
    
    if (rfidData.isFirstTap) {
        // Get physical card number
        const physicalCardNumber = getPhysicalCardNumber(rfidData.cardUID);
        
        // First tap - assign RFID for check-in
        rfidStatus.textContent = 'RFID Card Detected!';
        rfidMessage.textContent = `${physicalCardNumber} assigned successfully`;
        assignedTag.innerHTML = `
            <div class="text-center">
                <div class="text-3xl font-mono font-bold text-primary mb-1">${rfidData.customUID}</div>
                <div class="text-sm text-gray-600">${physicalCardNumber}</div>
              
            </div>
        `;
        
        // Hide the pulse animation
        if (pulseIndicator) {
            pulseIndicator.style.display = 'none';
        }
        
        // Store RFID data
        petData.rfidTag = rfidData.customUID;
        rfidAssigned = true;
        
        // Enable complete button
        const completeBtn = document.getElementById('completeBtn');
        completeBtn.disabled = false;
        completeBtn.className = 'bg-green-600 hover:bg-green-700 text-white px-8 py-3 rounded-lg font-medium transition-colors';
        
        // Stop polling
        stopRFIDPolling();
        
        showNotification(`${physicalCardNumber} detected and assigned!`, 'success');
        
    } else {
        // Get physical card number for subsequent taps too
        const physicalCardNumber = getPhysicalCardNumber(rfidData.cardUID);
        
        // Subsequent tap - show status update message
        rfidStatus.textContent = `RFID Tap #${rfidData.tapCount} Detected`;
        rfidMessage.textContent = `${physicalCardNumber} - Pet status updated`;
        showNotification(`${physicalCardNumber} tap #${rfidData.tapCount} logged - Status updated`, 'info');
    }
}

// Add this variable at the top with other global variables
// Add this variable at the top with other global variables
let isProcessingBooking = false;

async function completeBooking() {
    if (!rfidAssigned || !petData.rfidTag) {
        showNotification('Please wait for RFID assignment before completing check-in', 'warning');
        return;
    }
    
    // Prevent multiple clicks
    if (isProcessingBooking) {
        showNotification('Booking is already being processed, please wait...', 'info');
        return;
    }
    
    try {
        // Set processing state
        isProcessingBooking = true;
        
        // Disable the button and show loading state
        const completeBtn = document.getElementById('completeBtn');
        const originalText = completeBtn.innerHTML;
        completeBtn.disabled = true;
        completeBtn.className = 'bg-gray-400 text-gray-600 px-8 py-3 rounded-lg font-medium cursor-not-allowed flex items-center';
        completeBtn.innerHTML = `
            <svg class="animate-spin -ml-1 mr-3 h-5 w-5 text-gray-600" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
            </svg>
            Processing Booking...
        `;
        
        // Also disable back button to prevent navigation during processing
        const backBtn = document.querySelector('button[onclick="previousStep()"]');
        if (backBtn) {
            backBtn.disabled = true;
            backBtn.className = 'bg-gray-200 text-gray-400 px-8 py-3 rounded-lg font-medium cursor-not-allowed border border-gray-300';
        }
        
        showNotification('Creating booking and sending confirmation email...', 'info');
        
        const bookingData = {
            petName: petData.petName,
            petType: petData.petType,
            petBreed: petData.petBreed,
            petAge: petData.petAge,
            petSize: petData.petSize,
            selectedPetSize: currentPetSize || petData.selectedPetSize, // Add the size used for pricing
            ownerName: petData.ownerName,
            ownerPhone: petData.ownerPhone,
            ownerEmail: petData.ownerEmail,
            specialNotes: petData.specialNotes,
            services: selectedServices,
            totalAmount: parseFloat(totalAmount.toFixed(2)),
            customRFID: petData.rfidTag
        };

        console.log('Sending booking data:', bookingData);
        console.log('API URL:', API_BASE + 'check_in.php');

       const response = await fetch(API_BASE + 'check_in.php', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(bookingData)
        });

        // Check if response is actually JSON before parsing
        const responseText = await response.text();
        console.log('Raw response:', responseText); // Debug log

        let result;
        try {
            result = JSON.parse(responseText);
        } catch (parseError) {
            console.error('JSON parse error:', parseError);
            console.error('Response text:', responseText);
            throw new Error('Server returned invalid response. Check console for details.');
        }

        if (result.success) {
            bookingId = result.booking_id;
            
            // Show success message
            document.getElementById('finalTagId').textContent = petData.rfidTag;
            document.getElementById('finalBookingId').textContent = bookingId;
            goToStep('success');
            
            // Show different notification based on email status
            if (result.email_sent && result.tracking_email_sent) {
                showNotification('Check-in completed! Confirmation and tracking emails sent.', 'success');
            } else if (result.email_sent || result.tracking_email_sent) {
                showNotification('Check-in completed! Some email notifications sent.', 'warning');
            } else {
                showNotification('Check-in completed! (Email notifications failed)', 'warning');
            }
            
        } else {
            throw new Error(result.error || 'Failed to create booking');
        }
        
    } catch (error) {
        console.error('Error creating booking:', error);
        showNotification('Error creating booking: ' + error.message, 'error');
        
        // Reset button state on error
        const completeBtn = document.getElementById('completeBtn');
        completeBtn.disabled = false;
        completeBtn.className = 'bg-green-600 hover:bg-green-700 text-white px-8 py-3 rounded-lg font-medium transition-colors';
        completeBtn.innerHTML = 'Complete Check-in';
        
        // Re-enable back button
        const backBtn = document.querySelector('button[onclick="previousStep()"]');
        if (backBtn) {
            backBtn.disabled = false;
            backBtn.className = 'inline-flex items-center px-8 py-3 bg-gray-100 hover:bg-gray-200 text-gray-700 rounded-lg font-medium transition-all duration-200 border border-gray-300';
        }
        
    } finally {
        // Always reset processing state
        isProcessingBooking = false;
    }
}

function updateBookingSummary() {
    document.getElementById('summaryPetName').textContent = petData.petName;
    document.getElementById('summaryPetDetails').textContent = `${petData.petType} - ${petData.petBreed}${petData.petAge ? ` • ${petData.petAge}` : ''}${currentPetSize ? ` • ${currentPetSize}` : ''}`;
    document.getElementById('summaryOwnerName').textContent = petData.ownerName;
    document.getElementById('summaryOwnerContact').textContent = `${petData.ownerPhone}${petData.ownerEmail ? ` • ${petData.ownerEmail}` : ''}`;
    
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

// Update the existing showNotification function
function showNotification(message, type = 'info') {
    // Remove any existing processing notifications to avoid spam
    if (type === 'info' && message.includes('Processing') || message.includes('Creating booking')) {
        const existingNotifications = document.querySelectorAll('.notification-processing');
        existingNotifications.forEach(notif => notif.remove());
    }
    
    const notification = document.createElement('div');
    const colors = {
        success: 'bg-green-500',
        error: 'bg-red-500',
        warning: 'bg-yellow-500',
        info: 'bg-blue-500'
    };
    
    const icons = {
        success: '✓',
        error: '✕',
        warning: '⚠',
        info: 'ℹ'
    };
    
    notification.className = `fixed top-4 right-4 ${colors[type]} text-white px-6 py-4 rounded-lg shadow-lg z-50 transform translate-x-full transition-transform duration-300 flex items-center notification-${type}`;
    
    // Add processing class for processing notifications
    if (message.includes('Processing') || message.includes('Creating booking')) {
        notification.classList.add('notification-processing');
    }
    
    notification.innerHTML = `
        <span class="mr-2 text-lg">${icons[type]}</span>
        <span>${message}</span>
    `;
    
    document.body.appendChild(notification);
    
    // Animate in
    setTimeout(() => {
        notification.classList.remove('translate-x-full');
    }, 100);
    
    // Remove after appropriate time (longer for processing messages)
    const duration = message.includes('Processing') || message.includes('Creating booking') ? 8000 : 4000;
    setTimeout(() => {
        notification.classList.add('translate-x-full');
        setTimeout(() => {
            notification.remove();
        }, 300);
    }, duration);
}

function openGuestTracker() {
    // Always redirect to the tracking input page
    window.open('guest_pet_tracker.html', '_blank');
}

function generatePDFReceipt() {
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
    const finalHeight = Math.max(estimatedHeight - 25);
    
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
    doc.text(`ID: #${bookingId || 'N/A'} | RFID: ${petData.rfidTag || 'N/A'}`, 5, yPos);
    yPos += 5;
    
    // Pet Info - Compact
    doc.setFont('helvetica', 'bold');
    doc.text('PET INFO', 5, yPos);
    yPos += 3;
    doc.setFont('helvetica', 'normal');
    doc.text(`${petData.petName || 'N/A'} (${petData.petType || 'N/A'})`, 5, yPos);
    yPos += 3;
    doc.text(`${petData.petBreed || 'N/A'}`, 5, yPos);
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
    doc.text(petData.ownerName || 'N/A', 5, yPos);
    yPos += 3;
    doc.text(petData.ownerPhone || 'N/A', 5, yPos);
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
    if (selectedServices.length > 0) {
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
    } else {
        doc.text('No services selected', 5, yPos);
        yPos += 3;
    }
    
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