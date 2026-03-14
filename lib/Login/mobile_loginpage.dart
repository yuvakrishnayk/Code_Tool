import 'package:atom/Forgotpassword/mobile_forgotpage.dart';
import 'package:atom/SignUp/mobile_signuppage.dart';
import 'package:atom/pages/desktop_page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MobileLoginPage extends StatefulWidget {
  const MobileLoginPage({super.key});

  @override
  State<MobileLoginPage> createState() => _MobileLoginPageState();
}

class _MobileLoginPageState extends State<MobileLoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscureText = true;
  bool _isLoading = false;
  late AnimationController _animationController;

  // Add hover state variables
  bool _isEmailHovered = false;
  bool _isPasswordHovered = false;

  // Blue highlight color for hover effects
  final Color _highlightColor = Color(0xFF2196F3); // Material blue

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
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void signIn(String email, String password) {
    setState(() {
      _isLoading = true;
    });

    // Simulate network delay
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isLoading = false;
      });
      // Navigate to DesktopPage after successful login
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => DesktopPage()),
      );
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
                'Welcome Back',
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 20),
              Text(
                'Login to access your dashboard and continue your journey with us',
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
                      onEnter: (_) => setState(() => _isEmailHovered = true),
                      onExit: (_) => setState(() => _isEmailHovered = false),
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
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey[700],
                          ),
                          prefixIcon: Icon(
                            Icons.email_outlined,
                            color: Colors.grey[600],
                          ),
                          filled: true,
                          fillColor: Color(
                            0xFF141414,
                          ), // Slightly lighter black
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _highlightColor,
                              width: 1.5,
                            ), // Blue focus border
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
                            ), // Blue highlight on hover
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    SizedBox(height: 24),
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
                      onEnter: (_) => setState(() => _isPasswordHovered = true),
                      onExit: (_) => setState(() => _isPasswordHovered = false),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscureText,
                        style: GoogleFonts.poppins(color: Colors.white),
                        validator: (value) {
                          if (value!.length <= 6) {
                            return 'Password should be greater than 6';
                          } else {
                            return null;
                          }
                        },
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: GoogleFonts.poppins(
                            color: Colors.grey[700],
                          ),
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: Colors.grey[600],
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureText
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureText = !_obscureText;
                              });
                            },
                          ),
                          filled: true,
                          fillColor: Color(
                            0xFF141414,
                          ), // Slightly lighter black
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _highlightColor,
                              width: 1.5,
                            ), // Blue focus border
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
                            ), // Blue highlight on hover
                          ),
                          contentPadding: EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                    Container(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => MobileForgotPasswordPage(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text(
                          'Forgot Password?',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            _isLoading
                                ? null
                                : () {
                                  if (_formKey.currentState!.validate()) {
                                    signIn(
                                      _emailController.text,
                                      _passwordController.text,
                                    );
                                  }
                                },
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
                                  'Login',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.05),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Not Having an Account?',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[500],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MobileSignUpPage(),
                              ),
                            );
                          },
                          child: Text(
                            'Sign Up',
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
