import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MobileSignUpPage extends StatefulWidget {
  const MobileSignUpPage({super.key});

  @override
  State<MobileSignUpPage> createState() => _MobileSignUpPageState();
}

class _MobileSignUpPageState extends State<MobileSignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  late AnimationController _animationController;

  // Hover state variables
  bool _isFullNameHovered = false;
  bool _isEmailHovered = false;
  bool _isPasswordHovered = false;
  bool _isConfirmPasswordHovered = false;

  // Blue highlight color
  final Color _highlightColor = Color(0xFF2196F3);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _signUp() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // Simulate network delay for sign up
      Future.delayed(const Duration(seconds: 2), () {
        setState(() {
          _isLoading = false;
        });
        // Show success and navigate back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account created successfully! Please log in.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      });
    }
  }

  // Toggle password visibility
  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  // Toggle confirm password visibility
  void _toggleConfirmPasswordVisibility() {
    setState(() {
      _obscureConfirmPassword = !_obscureConfirmPassword;
    });
  }

  // Setter methods for hover states
  void _setFullNameHovered(bool value) {
    setState(() {
      _isFullNameHovered = value;
    });
  }

  void _setEmailHovered(bool value) {
    setState(() {
      _isEmailHovered = value;
    });
  }

  void _setPasswordHovered(bool value) {
    setState(() {
      _isPasswordHovered = value;
    });
  }

  void _setConfirmPasswordHovered(bool value) {
    setState(() {
      _isConfirmPasswordHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.08),
          child: Column(
            children: [
              SizedBox(height: screenHeight * 0.1),
              Center(
                child: Image.asset(
                  'assets/Image/logo.png',
                  width: screenWidth * 0.5,
                ),
              ),
              SizedBox(height: 30),
              Text(
                'Create Account',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Join us today and start exploring our platform with full access',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                  letterSpacing: 0.2,
                ),
              ),
              SizedBox(height: 40),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    SizedBox(height: 20),
                    // Full Name field
                    Text(
                      'Full Name',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[300],
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    MouseRegion(
                      onEnter: (_) => _setFullNameHovered(true),
                      onExit: (_) => _setFullNameHovered(false),
                      child: TextFormField(
                        controller: _fullNameController,
                        style: GoogleFonts.poppins(color: Colors.white),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your full name';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'John Doe',
                          hintStyle: GoogleFonts.poppins(color: Colors.grey[700]),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: Colors.grey[600],
                          ),
                          filled: true,
                          fillColor: Color(0xFF141414),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _highlightColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.redAccent.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                                  _isFullNameHovered
                                      ? _highlightColor
                                      : Color(0xFF1A1A1A),
                              width: _isFullNameHovered ? 1.5 : 1,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    // Email field
                    Text(
                      'Email Address',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[300],
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    MouseRegion(
                      onEnter: (_) => _setEmailHovered(true),
                      onExit: (_) => _setEmailHovered(false),
                      child: TextFormField(
                        controller: _emailController,
                        style: GoogleFonts.poppins(color: Colors.white),
                        validator: (value) {
                          if (value == null || !value.contains('@')) {
                            return 'Enter a valid email address';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: 'abc@gmail.com',
                          hintStyle: GoogleFonts.poppins(color: Colors.grey[700]),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: Colors.grey[600],
                          ),
                          filled: true,
                          fillColor: Color(0xFF141414),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _highlightColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.redAccent.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                                  _isEmailHovered
                                      ? _highlightColor
                                      : Color(0xFF1A1A1A),
                              width: _isEmailHovered ? 1.5 : 1,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    // Password field
                    Text(
                      'Password',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[300],
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    MouseRegion(
                      onEnter: (_) => _setPasswordHovered(true),
                      onExit: (_) => _setPasswordHovered(false),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: GoogleFonts.poppins(color: Colors.white),
                        validator: (value) {
                          if (value == null || value.length <= 6) {
                            return 'Password should be greater than 6 characters';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: GoogleFonts.poppins(color: Colors.grey[700]),
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: Colors.grey[600],
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            onPressed: _togglePasswordVisibility,
                          ),
                          filled: true,
                          fillColor: Color(0xFF141414),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _highlightColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.redAccent.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                                  _isPasswordHovered
                                      ? _highlightColor
                                      : Color(0xFF1A1A1A),
                              width: _isPasswordHovered ? 1.5 : 1,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
                    // Confirm Password field
                    Text(
                      'Confirm Password',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[300],
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    MouseRegion(
                      onEnter: (_) => _setConfirmPasswordHovered(true),
                      onExit: (_) => _setConfirmPasswordHovered(false),
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        style: GoogleFonts.poppins(color: Colors.white),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (value != _passwordController.text) {
                            return 'Passwords don\'t match';
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: GoogleFonts.poppins(color: Colors.grey[700]),
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: Colors.grey[600],
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            onPressed: _toggleConfirmPasswordVisibility,
                          ),
                          filled: true,
                          fillColor: Color(0xFF141414),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _highlightColor,
                              width: 1.5,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.redAccent.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                                  _isConfirmPasswordHovered
                                      ? _highlightColor
                                      : Color(0xFF1A1A1A),
                              width: _isConfirmPasswordHovered ? 1.5 : 1,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 40),
                    // Sign Up button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF1A1A1A),
                          disabledBackgroundColor: Color(
                            0xFF1A1A1A,
                          ).withOpacity(0.6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            _isLoading
                                ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                                : Text(
                                  'Create Account',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.04),
                    // Login link
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Already have an account?',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Login',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[300],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
