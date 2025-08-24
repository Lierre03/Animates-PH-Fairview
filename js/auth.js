  // API base URL - adjust this to your server location
        const API_BASE = 'http://localhost/animates/api/';
        
        let verificationToken = null;
        let resendTimer = null;
        let resetToken = null;
        let resendResetTimer = null;

        // Form switching functions
        function showLoginForm() {
            hideAllForms();
            document.getElementById('login-form').classList.remove('hidden');
        }

        function showSignupForm() {
            hideAllForms();
            document.getElementById('signup-form').classList.remove('hidden');
        }

        function showVerificationForm() {
            hideAllForms();
            document.getElementById('verification-form').classList.remove('hidden');
        }

        function showForgotPassword() {
            hideAllForms();
            document.getElementById('forgot-password-form').classList.remove('hidden');
        }

        function showResetCodeForm() {
            hideAllForms();
            document.getElementById('reset-code-form').classList.remove('hidden');
        }

        function showNewPasswordForm() {
            hideAllForms();
            document.getElementById('new-password-form').classList.remove('hidden');
        }

        function hideAllForms() {
            document.querySelectorAll('#login-form, #signup-form, #verification-form, #forgot-password-form, #reset-code-form, #new-password-form').forEach(form => {
                form.classList.add('hidden');
            });
        }
        // Password visibility toggle
        function togglePassword(inputId) {
            const input = document.getElementById(inputId);
            const type = input.type === 'password' ? 'text' : 'password';
            input.type = type;
        }

        // Password strength checker
        function checkPasswordStrength(password) {
            let strength = 0;
            let feedback = [];

            if (password.length >= 8) strength++;
            else feedback.push("At least 8 characters");

            if (/[a-z]/.test(password) && /[A-Z]/.test(password)) strength++;
            else feedback.push("Mix of uppercase & lowercase");

            if (/\d/.test(password)) strength++;
            else feedback.push("Include numbers");

            if (/[^A-Za-z0-9]/.test(password)) strength++;
            else feedback.push("Include special characters");

            return { strength, feedback };
        }

        function updatePasswordStrength() {
            const password = document.getElementById('signupPassword').value;
            const bars = document.querySelectorAll('.password-bar');
            const text = document.querySelector('.password-text');
            
            if (!password) {
                bars.forEach(bar => bar.className = 'password-bar bg-gray-200 rounded-full h-1 flex-1');
                text.textContent = 'Enter a password';
                text.className = 'password-text text-gray-500 mt-1';
                return;
            }

            const { strength, feedback } = checkPasswordStrength(password);
            const colors = ['bg-red-500', 'bg-orange-500', 'bg-yellow-500', 'bg-green-500'];
            const texts = ['Very Weak', 'Weak', 'Good', 'Strong'];
            const textColors = ['text-red-600', 'text-orange-600', 'text-yellow-600', 'text-green-600'];

            bars.forEach((bar, index) => {
                bar.className = `password-bar rounded-full h-1 flex-1 ${index < strength ? colors[strength - 1] : 'bg-gray-200'}`;
            });

            text.textContent = feedback.length ? feedback.join(', ') : texts[strength - 1];
            text.className = `password-text mt-1 ${feedback.length ? 'text-gray-600' : textColors[strength - 1]}`;
        }

        function checkPasswordMatch() {
            const password = document.getElementById('signupPassword').value;
            const confirm = document.getElementById('confirmPassword').value;
            const matchDiv = document.getElementById('password-match');
            
            if (!confirm) {
                matchDiv.textContent = '';
                return false;
            }
            
            if (password === confirm) {
                matchDiv.textContent = '✓ Passwords match';
                matchDiv.className = 'mt-1 text-xs text-green-600';
                return true;
            } else {
                matchDiv.textContent = '✗ Passwords do not match';
                matchDiv.className = 'mt-1 text-xs text-red-600';
                return false;
            }
        }

        function validateSignupForm() {
            const requiredFields = ['firstName', 'lastName', 'signupEmail', 'signupPhone', 'signupAddress', 'emergencyContactName', 'emergencyContactNo', 'signupPassword', 'confirmPassword'];            const allFilled = requiredFields.every(field => document.getElementById(field).value.trim());
            const termsChecked = document.getElementById('agreeTerms').checked;
            const passwordsMatch = checkPasswordMatch();
            const { strength } = checkPasswordStrength(document.getElementById('signupPassword').value);
            
            const signupBtn = document.getElementById('signupBtn');
            const isValid = allFilled && termsChecked && passwordsMatch && strength >= 2;
            
            if (isValid) {
                signupBtn.disabled = false;
                signupBtn.className = 'w-full bg-primary hover:bg-blue-700 text-white py-3 rounded-lg font-medium transition-colors';
            } else {
                signupBtn.disabled = true;
                signupBtn.className = 'w-full bg-gray-300 text-gray-500 py-3 rounded-lg font-medium cursor-not-allowed transition-colors';
            }
        }

        function setupResetCodeInputs() {
            const inputs = document.querySelectorAll('.reset-code-input');
            inputs.forEach((input, index) => {
                input.addEventListener('input', (e) => {
                    if (e.target.value && index < inputs.length - 1) {
                        inputs[index + 1].focus();
                    }
                    checkResetCode();
                });
                
                input.addEventListener('keydown', (e) => {
                    if (e.key === 'Backspace' && !e.target.value && index > 0) {
                        inputs[index - 1].focus();
                    }
                });
            });
        }

        function checkResetCode() {
            const inputs = document.querySelectorAll('.reset-code-input');
            const code = Array.from(inputs).map(input => input.value).join('');
            const verifyBtn = document.getElementById('verifyResetCodeBtn');
            
            if (code.length === 6) {
                verifyBtn.disabled = false;
                verifyBtn.className = 'w-full bg-primary hover:bg-blue-700 text-white py-3 rounded-lg font-medium transition-colors';
            } else {
                verifyBtn.disabled = true;
                verifyBtn.className = 'w-full bg-gray-300 text-gray-500 py-3 rounded-lg font-medium cursor-not-allowed transition-colors';
            }
        }

        function startResendResetTimer() {
            let seconds = 60;
            const timerDiv = document.getElementById('resendResetTimer');
            const countdownSpan = document.getElementById('resetCountdown');
            const resendBtn = document.getElementById('resendResetBtn');
            
            timerDiv.classList.remove('hidden');
            resendBtn.disabled = true;
            resendBtn.className = 'text-gray-400 font-medium cursor-not-allowed';
            
            resendResetTimer = setInterval(() => {
                seconds--;
                countdownSpan.textContent = seconds;
                
                if (seconds <= 0) {
                    clearInterval(resendResetTimer);
                    timerDiv.classList.add('hidden');
                    resendBtn.disabled = false;
                    resendBtn.className = 'text-primary hover:text-blue-700 font-medium';
                }
            }, 1000);
        }

        // Verification code handling
        function setupVerificationInputs() {
            const inputs = document.querySelectorAll('.verification-input');
            inputs.forEach((input, index) => {
                input.addEventListener('input', (e) => {
                    if (e.target.value && index < inputs.length - 1) {
                        inputs[index + 1].focus();
                    }
                    checkVerificationCode();
                });
                
                input.addEventListener('keydown', (e) => {
                    if (e.key === 'Backspace' && !e.target.value && index > 0) {
                        inputs[index - 1].focus();
                    }
                });
            });
        }

        function checkVerificationCode() {
            const inputs = document.querySelectorAll('.verification-input');
            const code = Array.from(inputs).map(input => input.value).join('');
            const verifyBtn = document.getElementById('verifyBtn');
            
            if (code.length === 6) {
                verifyBtn.disabled = false;
                verifyBtn.className = 'w-full bg-primary hover:bg-blue-700 text-white py-3 rounded-lg font-medium transition-colors';
            } else {
                verifyBtn.disabled = true;
                verifyBtn.className = 'w-full bg-gray-300 text-gray-500 py-3 rounded-lg font-medium cursor-not-allowed transition-colors';
            }
        }

        function startResendTimer() {
            let seconds = 60;
            const timerDiv = document.getElementById('resendTimer');
            const countdownSpan = document.getElementById('countdown');
            const resendBtn = document.getElementById('resendBtn');
            
            timerDiv.classList.remove('hidden');
            resendBtn.disabled = true;
            resendBtn.className = 'text-gray-400 font-medium cursor-not-allowed';
            
            resendTimer = setInterval(() => {
                seconds--;
                countdownSpan.textContent = seconds;
                
                if (seconds <= 0) {
                    clearInterval(resendTimer);
                    timerDiv.classList.add('hidden');
                    resendBtn.disabled = false;
                    resendBtn.className = 'text-primary hover:text-blue-700 font-medium';
                }
            }, 1000);
        }

        // Form submission handlers
        async function handleLogin(e) {
            e.preventDefault();
            
            const email = document.getElementById('loginEmail').value;
            const password = document.getElementById('loginPassword').value;
            
            try {
                showNotification('Signing in...', 'info');
                
                const response = await fetch(`${API_BASE}auth.php`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        action: 'login',
                        email: email,
                        password: password
                    })
                });
                
                const result = await response.json();
                
                // Replace the existing handleLogin success block with this:
                if (result.success) {
                    // Store auth token
                    localStorage.setItem('authToken', result.token);
                    localStorage.setItem('userId', result.user_id);
                    localStorage.setItem('userRole', result.user.role); // Store user role
                    
                    showNotification('Welcome back! Redirecting...', 'success');
                    
                    // Redirect based on user role
                    setTimeout(() => {
                        if (result.user.role === 'customer') {
                            window.location.href = 'customer_portal.html';
                        } else if (result.user.role === 'admin' || result.user.role === 'staff') {
                            window.location.href = 'dashboard.html';
                        } else {
                            // Fallback to customer portal for unknown roles
                            window.location.href = 'customer_portal.html';
                        }
                    }, 2000);
                } else {
                    showNotification(result.error || 'Login failed', 'error');
                }
            } catch (error) {
                console.error('Login error:', error);
                showNotification('Connection error. Please try again.', 'error');
            }
        }

        async function handleSignup(e) {
    e.preventDefault();
    
    const formData = {
        firstName: document.getElementById('firstName').value,
        lastName: document.getElementById('lastName').value,
        email: document.getElementById('signupEmail').value,
        phone: document.getElementById('signupPhone').value,
        address: document.getElementById('signupAddress').value,
        emergencyContactName: document.getElementById('emergencyContactName').value,
        emergencyContactNo: document.getElementById('emergencyContactNo').value,
        password: document.getElementById('signupPassword').value,
        // marketingEmails: document.getElementById('marketingEmails').checked
    };
    
    try {
        showNotification('Creating your account...', 'info');
        
        const response = await fetch(`${API_BASE}auth.php`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                action: 'signup',
                ...formData
            })
        });

        // Check if the response is successful first
        if (!response.ok) {
            const errorText = await response.text();
            showNotification(`Server error: ${errorText}`, 'error');
            console.error('Server responded with an error:', errorText);
            return; // Stop execution
        }
        
        const result = await response.json();
        
        if (result.success) {
            verificationToken = result.verification_token;
            document.getElementById('verificationEmail').textContent = formData.email;
            
            showNotification('Verification email sent! Please check your inbox.', 'success');
            showVerificationForm();
            startResendTimer();
        } else {
            showNotification(result.error || 'Signup failed', 'error');
        }
    } catch (error) {
        console.error('Signup error:', error);
        showNotification('Connection error or invalid response. Please try again.', 'error');
    }
}

        async function handleVerification(e) {
            e.preventDefault();
            
            const inputs = document.querySelectorAll('.verification-input');
            const code = Array.from(inputs).map(input => input.value).join('');
            
            try {
                showNotification('Verifying your email...', 'info');
                
                const response = await fetch(`${API_BASE}auth.php`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        action: 'verify_email',
                        verification_token: verificationToken,
                        verification_code: code
                    })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    // Store auth token
                    localStorage.setItem('authToken', result.token);
                    localStorage.setItem('userId', result.user_id);
                    
                    showNotification('Email verified successfully! Welcome to 8Paws!', 'success');
                    
                    // Redirect to customer portal
                    setTimeout(() => {
                        window.location.href = 'customer_portal.html';
                    }, 2000);
                } else {
                    showNotification(result.error || 'Verification failed', 'error');
                    // Clear the inputs on error
                    inputs.forEach(input => input.value = '');
                    inputs[0].focus();
                }
            } catch (error) {
                console.error('Verification error:', error);
                showNotification('Connection error. Please try again.', 'error');
            }
        }

        async function handleForgotPassword(e) {
            e.preventDefault();
            
            const email = document.getElementById('resetEmail').value;
            
            try {
                showNotification('Sending reset code...', 'info');
                
                const response = await fetch(`${API_BASE}auth.php`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        action: 'forgot_password',
                        email: email
                    })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    resetToken = result.reset_token;
                    document.getElementById('resetCodeEmail').textContent = email;
                    
                    showNotification('Reset code sent to your email!', 'success');
                    showResetCodeForm();
                    startResendResetTimer();
                } else {
                    showNotification(result.error || 'Failed to send reset code', 'error');
                }
            } catch (error) {
                console.error('Forgot password error:', error);
                showNotification('Connection error. Please try again.', 'error');
            }
        }

        async function handleResetCodeVerification(e) {
    e.preventDefault();
    
    const inputs = document.querySelectorAll('.reset-code-input');
    const code = Array.from(inputs).map(input => input.value).join('');
    
    try {
        showNotification('Verifying reset code...', 'info');
        
        const response = await fetch(`${API_BASE}auth.php`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                action: 'verify_reset_code',
                reset_token: resetToken,
                reset_code: code
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            showNotification('Code verified! Set your new password.', 'success');
            showNewPasswordForm();
        } else {
            showNotification(result.error || 'Verification failed', 'error');
            inputs.forEach(input => input.value = '');
            inputs[0].focus();
        }
    } catch (error) {
        console.error('Reset code verification error:', error);
        showNotification('Connection error. Please try again.', 'error');
    }
}

async function handleNewPassword(e) {
    e.preventDefault();
    
    const inputs = document.querySelectorAll('.reset-code-input');
    const code = Array.from(inputs).map(input => input.value).join('');
    const password = document.getElementById('newPassword').value;
    
    try {
        showNotification('Resetting password...', 'info');
        
        const response = await fetch(`${API_BASE}auth.php`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                action: 'reset_password',
                reset_token: resetToken,
                reset_code: code,
                password: password
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            showNotification('Password reset successfully! Please sign in.', 'success');
            setTimeout(() => {
                showLoginForm();
            }, 2000);
        } else {
            showNotification(result.error || 'Password reset failed', 'error');
        }
    } catch (error) {
        console.error('Password reset error:', error);
        showNotification('Connection error. Please try again.', 'error');
    }
}

async function resendResetCode() {
    if (resendResetTimer) return;
    
    try {
        showNotification('Resending reset code...', 'info');
        
        const response = await fetch(`${API_BASE}auth.php`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                action: 'resend_reset_code',
                reset_token: resetToken
            })
        });
        
        const result = await response.json();
        
        if (result.success) {
            showNotification('New reset code sent!', 'success');
            startResendResetTimer();
            
            document.querySelectorAll('.reset-code-input').forEach(input => {
                input.value = '';
            });
            document.querySelector('.reset-code-input').focus();
        } else {
            showNotification(result.error || 'Failed to resend code', 'error');
        }
    } catch (error) {
        console.error('Resend reset code error:', error);
        showNotification('Connection error. Please try again.', 'error');
    }
}

        async function resendVerification() {
            if (resendTimer) return; // Timer is still running
            
            try {
                showNotification('Resending verification code...', 'info');
                
                const response = await fetch(`${API_BASE}auth.php`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify({
                        action: 'resend_verification',
                        verification_token: verificationToken
                    })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    showNotification('New verification code sent!', 'success');
                    startResendTimer();
                    
                    // Clear current inputs
                    document.querySelectorAll('.verification-input').forEach(input => {
                        input.value = '';
                    });
                    document.querySelector('.verification-input').focus();
                } else {
                    showNotification(result.error || 'Failed to resend code', 'error');
                }
            } catch (error) {
                console.error('Resend verification error:', error);
                showNotification('Connection error. Please try again.', 'error');
            }
        }

        // Phone number formatting
        function formatPhoneNumber(input) {
            let value = input.value.replace(/\D/g, '');
            if (value.length > 0) {
                if (value.length <= 4) {
                    value = value;
                } else if (value.length <= 7) {
                    value = value.slice(0, 4) + '-' + value.slice(4);
                } else {
                    value = value.slice(0, 4) + '-' + value.slice(4, 7) + '-' + value.slice(7, 11);
                }
            }
            input.value = value;
        }


        function updateNewPasswordStrength() {
            const password = document.getElementById('newPassword').value;
            const bars = document.querySelectorAll('.new-password-bar');
            const text = document.querySelector('.new-password-text');
            
            if (!password) {
                bars.forEach(bar => bar.className = 'new-password-bar bg-gray-200 rounded-full h-1 flex-1');
                text.textContent = 'Enter a password';
                text.className = 'new-password-text text-gray-500 mt-1';
                return;
            }

            const { strength, feedback } = checkPasswordStrength(password);
            const colors = ['bg-red-500', 'bg-orange-500', 'bg-yellow-500', 'bg-green-500'];
            const texts = ['Very Weak', 'Weak', 'Good', 'Strong'];
            const textColors = ['text-red-600', 'text-orange-600', 'text-yellow-600', 'text-green-600'];

            bars.forEach((bar, index) => {
                bar.className = `new-password-bar rounded-full h-1 flex-1 ${index < strength ? colors[strength - 1] : 'bg-gray-200'}`;
            });

            text.textContent = feedback.length ? feedback.join(', ') : texts[strength - 1];
            text.className = `new-password-text mt-1 ${feedback.length ? 'text-gray-600' : textColors[strength - 1]}`;
            }

            function checkNewPasswordMatch() {
            const password = document.getElementById('newPassword').value;
            const confirm = document.getElementById('confirmNewPassword').value;
            const matchDiv = document.getElementById('new-password-match');
            
            if (!confirm) {
                matchDiv.textContent = '';
                return false;
            }
            
            if (password === confirm) {
                matchDiv.textContent = '✓ Passwords match';
                matchDiv.className = 'mt-1 text-xs text-green-600';
                return true;
            } else {
                matchDiv.textContent = '✗ Passwords do not match';
                matchDiv.className = 'mt-1 text-xs text-red-600';
                return false;
            }
            }

            function validateNewPasswordForm() {
            const password = document.getElementById('newPassword').value;
            const confirmPassword = document.getElementById('confirmNewPassword').value;
            const passwordsMatch = checkNewPasswordMatch();
            const { strength } = checkPasswordStrength(password);
            
            const resetBtn = document.getElementById('resetPasswordBtn');
            const isValid = password.trim() && confirmPassword.trim() && passwordsMatch && strength >= 2;
            
            if (isValid) {
                resetBtn.disabled = false;
                resetBtn.className = 'w-full bg-primary hover:bg-blue-700 text-white py-3 rounded-lg font-medium transition-colors';
            } else {
                resetBtn.disabled = true;
                resetBtn.className = 'w-full bg-gray-300 text-gray-500 py-3 rounded-lg font-medium cursor-not-allowed transition-colors';
            }
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

        // Initialize page
        document.addEventListener('DOMContentLoaded', function() {
            // Check if user is already logged in
            const token = localStorage.getItem('authToken');
            if (token) {
                // Verify token validity
                fetch(`${API_BASE}auth.php`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`
                    },
                    body: JSON.stringify({ action: 'verify_token' })
                })
                .then(response => response.json())
                .then(result => {
                    if (result.success) {
                        // Redirect to customer portal if token is valid
                        window.location.href = 'customer_portal.html';
                    } else {
                        // Remove invalid token
                        localStorage.removeItem('authToken');
                        localStorage.removeItem('userId');
                    }
                })
                .catch(() => {
                    // Remove token on error
                    localStorage.removeItem('authToken');
                    localStorage.removeItem('userId');
                });
            }
            
            // Set up form event listeners
            document.getElementById('loginForm').addEventListener('submit', handleLogin);
            document.getElementById('signupForm').addEventListener('submit', handleSignup);
            document.getElementById('verificationForm').addEventListener('submit', handleVerification);
            document.getElementById('forgotPasswordForm').addEventListener('submit', handleForgotPassword);
            document.getElementById('resetCodeForm').addEventListener('submit', handleResetCodeVerification);
            document.getElementById('newPasswordForm').addEventListener('submit', handleNewPassword);

            // Set up reset code inputs
            setupResetCodeInputs();
            
            // Set up verification code inputs
            setupVerificationInputs();
            
            // Set up phone number formatting
            document.getElementById('signupPhone').addEventListener('input', function() {
                formatPhoneNumber(this);
                validateSignupForm();
            });

            // Set up emergency contact phone number formatting
            document.getElementById('emergencyContactNo').addEventListener('input', function() {
                formatPhoneNumber(this);
                validateSignupForm();
            });
                        
            // Set up password validation
            document.getElementById('signupPassword').addEventListener('input', function() {
                updatePasswordStrength();
                validateSignupForm();
            });

            
            document.getElementById('confirmPassword').addEventListener('input', function() {
                checkPasswordMatch();
                validateSignupForm();
            });

            // Set up new password validation
            document.getElementById('newPassword').addEventListener('input', function() {
                updateNewPasswordStrength();
                validateNewPasswordForm();
            });

            document.getElementById('confirmNewPassword').addEventListener('input', function() {
                checkNewPasswordMatch();
                validateNewPasswordForm();
            });
            
            // Set up other form validation
            ['firstName', 'lastName', 'signupEmail', 'signupAddress', 'emergencyContactName'].forEach(fieldId => {
                document.getElementById(fieldId).addEventListener('input', validateSignupForm);
            });
            
            document.getElementById('agreeTerms').addEventListener('change', validateSignupForm);
            
            // Show login form by default
            showLoginForm();
            
            // Check URL parameters for special actions
            const urlParams = new URLSearchParams(window.location.search);
            const action = urlParams.get('action');
            
            if (action === 'signup') {
                showSignupForm();
            } else if (action === 'forgot') {
                showForgotPassword();
            }
        });