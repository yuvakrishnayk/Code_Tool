import 'package:atom/components/drawer.dart';
import 'package:atom/pages/notifications.dart';
import 'package:atom/pages/settings.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class DesktopPage extends StatefulWidget {
  DesktopPage({super.key});

  @override
  _DesktopPageState createState() => _DesktopPageState();
}

class _DesktopPageState extends State<DesktopPage>
    with TickerProviderStateMixin {
  String? fileContent; // Variable to hold the file content
  String? codeReviewOutput; // Variable to hold API response
  bool isTyping = false;
  final String selectedAnalysisType =
      'Thoroughly analyze this code for readability, best practices, errors, logic issues, security risks, and performance bottlenecks. Provide detailed improvement recommendations with examples.'; // Comprehensive fixed prompt
  final String _geminiApiKey =
      'AIzaSyDeEmDAmZpVuRUJkDooPSpiae3iROw4viY'; // Replace with your API key

  bool showQueryField = false; // To toggle the query field
  final TextEditingController queryController = TextEditingController();
  String? responseMessage;

  bool showChatbotUI = false; // To toggle the chatbot UI
  bool showGitReview = false; // To toggle the GitHub review UI
  bool showDebugPage = false; // To toggle the debug page UI
  final TextEditingController messageController = TextEditingController();
  final List<String> chatMessages = []; // To store chat messages

  // GitHub repo related variables
  final TextEditingController _repoUrlController = TextEditingController();
  bool _isProcessingRepo = false;
  String? _repoProcessStatus;
  String? _repoName;
  List<String> _repoFiles = [];
  int _currentFileIndex = -1;

  bool isGitHubFeatureEnabled =
      false; // Flag to control GitHub feature availability

  String selectedPage = ''; // Track the selected page

  TabController? _repoTabController; // For desktop GitHub UI
  TabController? _mobileRepoTabController; // For mobile GitHub UI

  // GitHub login related variables
  bool _isLoggedInToGitHub = false;
  String? _githubUsername;
  String? _githubToken; // Changed back to token instead of password
  List<Map<String, dynamic>> _userRepos = [];
  bool _isLoadingRepos = false;

  // Public repository lookup variables
  final TextEditingController _publicRepoUsernameController =
      TextEditingController();
  List<Map<String, dynamic>> _publicRepos = [];
  bool _isLoadingPublicRepos = false;
  String? _selectedPublicRepo;
  bool _showPublicRepoDropdown = false;

  @override
  void initState() {
    super.initState();
    // Will be initialized when repo files are loaded
  }

  @override
  void dispose() {
    _repoTabController?.dispose();
    _mobileRepoTabController?.dispose();
    _publicRepoUsernameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final fileName = file.name;

        if (file.bytes != null && file.bytes!.isNotEmpty) {
          // File has content in bytes (common for web and some mobile platforms)
          setState(() {
            fileContent = utf8.decode(file.bytes!);
          });
          await _analyzeCodeWithGemini(fileContent!, fileName);
        } else if (file.path != null && file.path!.isNotEmpty) {
          // For platforms where we have a file path but not bytes
          try {
            // Using dart:io File for reading instead of http.get
            // This works correctly on Android, iOS, and desktop platforms
            final fileData = await File(file.path!).readAsBytes();
            setState(() {
              fileContent = utf8.decode(fileData);
            });
            await _analyzeCodeWithGemini(fileContent!, fileName);
          } catch (e) {
            // If direct File reading fails, try alternative methods based on platform
            if (Platform.isAndroid) {
              // For Android, try using platform-specific path handling
              try {
                final pathSegments = file.path!.split('/');
                final name = pathSegments.last;
                final dir = await getApplicationDocumentsDirectory();
                final tempPath = '${dir.path}/$name';

                // Copy the file to a location we can access
                await File(tempPath).writeAsBytes(
                  await File(file.path!).readAsBytes(),
                  flush: true,
                );

                final fileData = await File(tempPath).readAsBytes();
                setState(() {
                  fileContent = utf8.decode(fileData);
                });
                await _analyzeCodeWithGemini(fileContent!, fileName);
              } catch (androidError) {
                _showErrorSnackbar('Error reading Android file: $androidError');
              }
            } else {
              _showErrorSnackbar('Error reading file: $e');
            }
          }
        } else {
          _showErrorSnackbar('File appears to be empty or inaccessible');
        }
      } else {
        print("No file selected");
      }
    } catch (e) {
      _showErrorSnackbar('Error selecting file: $e');
    }
  }

  // Helper method for showing error messages
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _guessLanguageFromFilename(String filename) {
    final extension = filename.split('.').last.toLowerCase();
    switch (extension) {
      case 'py':
        return 'Python';
      case 'java':
        return 'Java';
      case 'js':
        return 'JavaScript';
      case 'ts':
        return 'TypeScript';
      case 'c':
        return 'C';
      case 'cpp':
      case 'cc':
        return 'C++';
      case 'cs':
        return 'C#';
      case 'go':
        return 'Go';
      case 'rb':
        return 'Ruby';
      case 'php':
        return 'PHP';
      case 'html':
        return 'HTML';
      case 'css':
        return 'CSS';
      case 'swift':
        return 'Swift';
      case 'kt':
        return 'Kotlin';
      case 'dart':
        return 'Dart';
      case 'rs':
        return 'Rust';
      default:
        return 'Unknown';
    }
  }

  // GitHub repository methods
  Future<List<String>> _fetchGitHubFiles(String repoUrl) async {
    // Extract owner and repo name from URL
    final uri = Uri.parse(repoUrl);
    final segments = uri.pathSegments;
    if (segments.length < 2) throw Exception("Invalid GitHub repo URL");
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    // Get default branch
    final repoApiUrl = 'https://api.github.com/repos/$owner/$repo';
    final repoResp = await http.get(Uri.parse(repoApiUrl));
    if (repoResp.statusCode != 200) throw Exception("Repo not found");
    final repoData = jsonDecode(repoResp.body);
    final branch = repoData['default_branch'] ?? 'main';

    // Get file tree recursively
    final treeApiUrl =
        'https://api.github.com/repos/$owner/$repo/git/trees/$branch?recursive=1';
    final treeResp = await http.get(Uri.parse(treeApiUrl));
    if (treeResp.statusCode != 200) {
      throw Exception("Could not fetch repo tree");
    }
    final treeData = jsonDecode(treeResp.body);

    final List<String> files = [];
    for (final item in treeData['tree']) {
      if (item['type'] == 'blob') {
        files.add(item['path']);
      }
    }
    return files;
  }

  Future<void> _processGitRepository() async {
    final repoUrl = _repoUrlController.text.trim();
    if (repoUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid repository URL')),
      );
      return;
    }

    setState(() {
      _isProcessingRepo = true;
      _repoProcessStatus = "Fetching repository information...";
      _repoFiles = [];
      _currentFileIndex = -1;
      fileContent = null;
      codeReviewOutput = null;
      _repoTabController?.dispose();
      _repoTabController = null;
      _mobileRepoTabController?.dispose();
      _mobileRepoTabController = null;
    });

    try {
      // Extract repo name from URL
      _repoName = repoUrl.split('/').last.replaceAll('.git', '');

      setState(() {
        _repoProcessStatus = "Repository found. Loading files...";
      });

      final files = await _fetchGitHubFiles(repoUrl);

      setState(() {
        _repoFiles = files;
        _repoProcessStatus = "Repository loaded successfully!";
        _isProcessingRepo = false;
        // Initialize tab controllers after files are loaded
        _repoTabController = TabController(length: 2, vsync: this);
        _mobileRepoTabController = TabController(length: 2, vsync: this);
      });
    } catch (error) {
      setState(() {
        _repoProcessStatus = "Error: $error";
        _isProcessingRepo = false;
      });
    }
  }

  Future<String> _fetchGitHubFileContent(
    String repoUrl,
    String filePath,
  ) async {
    final uri = Uri.parse(repoUrl);
    final segments = uri.pathSegments;
    if (segments.length < 2) throw Exception("Invalid GitHub repo URL");
    final owner = segments[0];
    final repo = segments[1].replaceAll('.git', '');

    // Get default branch
    final repoApiUrl = 'https://api.github.com/repos/$owner/$repo';
    final repoResp = await http.get(Uri.parse(repoApiUrl));
    if (repoResp.statusCode != 200) throw Exception("Repo not found");
    final repoData = jsonDecode(repoResp.body);
    final branch = repoData['default_branch'] ?? 'main';

    // Build raw file URL
    final rawUrl =
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath';
    final fileResp = await http.get(Uri.parse(rawUrl));
    if (fileResp.statusCode != 200)
      throw Exception("Could not fetch file content");
    return fileResp.body;
  }

  Future<void> _loadRepositoryFile(int index) async {
    if (index < 0 || index >= _repoFiles.length) return;

    setState(() {
      _currentFileIndex = index;
      fileContent = "Loading file content...";
      codeReviewOutput = null;
    });

    final filename = _repoFiles[index];

    try {
      final repoUrl = _repoUrlController.text.trim();
      final content = await _fetchGitHubFileContent(repoUrl, filename);

      setState(() {
        fileContent = content;
      });

      // Analyze the file with Gemini
      await _analyzeCodeWithGemini(content, filename);
    } catch (e) {
      setState(() {
        fileContent = "Error loading file: $e";
      });
    }
  }

  Future<void> _analyzeRepositoryWithGemini() async {
    if (_repoName == null) return;

    // Switch to Analysis tab (index 1) for both desktop and mobile
    _repoTabController?.animateTo(1);
    _mobileRepoTabController?.animateTo(1);

    setState(() {
      codeReviewOutput = "Analyzing entire repository...";
      isTyping = true;
    });

    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash-lite:generateContent?key=$_geminiApiKey',
      );

      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        "contents": [
          {
            "parts": [
              {
                "text": """
                Act as an expert code reviewer. I have a repository named $_repoName with the following structure:
                
                ${_repoFiles.join('\n')}
                
                $selectedAnalysisType
                
                Provide your analysis in the following structured format:
                
                ## Repository Overview
                [Brief overview of the repository structure and purpose]
                
                ## Key Findings
                [List major issues or insights about the codebase]
                
                ## Architecture Assessment
                [Comments on the architecture and organization]
                
                ## Improvement Recommendations
                [High-level improvement recommendations]
                """,
              },
            ],
          },
        ],
      });

      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        setState(() {
          codeReviewOutput = responseText ?? "No analysis could be generated.";
          isTyping = false;
        });
      } else {
        setState(() {
          codeReviewOutput = "Error: ${response.statusCode}\n${response.body}";
          isTyping = false;
        });
      }
    } catch (error) {
      setState(() {
        codeReviewOutput = "Error: $error";
        isTyping = false;
      });
    }
  }

  Future<void> _analyzeCodeWithGemini(String code, String filename) async {
    setState(() {
      codeReviewOutput = "Analyzing your code...";
      isTyping = true;
    });

    final language = _guessLanguageFromFilename(filename);
    final requestPrompt = """
    Act as an expert $language developer and code reviewer. Analyze the following $language code:
    
    ```
    $code
    ```
    
    $selectedAnalysisType
    
    Provide your analysis in the following structured format:
    
    ## Summary
    [Brief summary of the code's purpose and overall quality]
    
    ## Code Style Issues
    [List any code style issues]
    
    ## Potential Errors
    [List any potential errors or bugs]
    
    ## Logic Issues
    [Point out any logical flaws or suboptimal implementations]
    
    ## Improvement Suggestions
    [Provide specific code improvement suggestions with examples]
    """;

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash-lite:generateContent?key=$_geminiApiKey',
    );

    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": requestPrompt},
          ],
        },
      ],
    });

    try {
      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (responseText == null) {
          setState(() {
            codeReviewOutput = "No analysis could be generated.";
            isTyping = false;
          });
        } else {
          setState(() {
            codeReviewOutput = responseText;
            isTyping = false;
          });
        }
      } else {
        setState(() {
          codeReviewOutput = "Error: ${response.statusCode}\n${response.body}";
          isTyping = false;
        });
      }
    } catch (error) {
      setState(() {
        codeReviewOutput = "Error: $error";
        isTyping = false;
      });
    }
  }

  // GitHub login dialog
  Future<void> _showGitHubLoginDialog() async {
    final usernameController = TextEditingController();
    final tokenController =
        TextEditingController(); // Changed back from passwordController

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('GitHub Login', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.grey.shade900,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: 'GitHub Username',
                    labelStyle: TextStyle(color: Colors.white),
                    hintStyle: TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey.shade800,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
                SizedBox(height: 16),
                TextField(
                  controller: tokenController,
                  decoration: InputDecoration(
                    labelText: 'Personal Access Token',
                    labelStyle: TextStyle(color: Colors.white),
                    hintText: 'Required for API access',
                    hintStyle: TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey.shade800,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                  obscureText: true,
                ),
                SizedBox(height: 10),
                Text(
                  'GitHub requires a Personal Access Token for API access. Create one at GitHub > Settings > Developer settings > Personal access tokens.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text('Login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
              ),
              onPressed: () {
                setState(() {
                  _githubUsername = usernameController.text;
                  _githubToken =
                      tokenController.text.isNotEmpty
                          ? tokenController.text
                          : null;
                  _isLoggedInToGitHub = true;
                });
                Navigator.of(context).pop();
                _fetchUserRepositories();
              },
            ),
          ],
        );
      },
    );
  }

  // Fetch user repositories
  Future<void> _fetchUserRepositories() async {
    if (_githubUsername == null) return;

    setState(() {
      _isLoadingRepos = true;
      _userRepos = [];
    });

    try {
      // If token is provided, we'll fetch all accessible repositories
      if (_githubToken != null && _githubToken!.isNotEmpty) {
        await _fetchAllAccessibleRepositories();
      } else {
        // Without token, we can only get public repositories of the user
        await _fetchPublicRepositories();
      }
    } catch (e) {
      setState(() {
        _isLoadingRepos = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching repositories: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // Fetch all repositories the user can access (requires token)
  Future<void> _fetchAllAccessibleRepositories() async {
    final userReposUrl = Uri.parse(
      'https://api.github.com/user/repos?per_page=100&sort=updated',
    );

    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      'Authorization': 'token $_githubToken', // Using token authentication
    };

    final List<Map<String, dynamic>> allRepos = [];

    try {
      // Fetch user's own repositories
      final userReposResponse = await http.get(userReposUrl, headers: headers);

      if (userReposResponse.statusCode == 200) {
        final List<dynamic> data = jsonDecode(userReposResponse.body);

        // Process each repository
        for (var repo in data) {
          allRepos.add({
            'name': repo['name'],
            'full_name': repo['full_name'],
            'description': repo['description'],
            'url': repo['html_url'],
            'stars': repo['stargazers_count'],
            'forks': repo['forks_count'],
            'private': repo['private'],
            'owner': repo['owner']?['login'] ?? '',
            'isOrg': false,
          });
        }
      } else {
        // Authentication failed
        throw Exception(
          'Authentication failed. Please check your Personal Access Token.',
        );
      }

      // Now also fetch repositories from organizations the user belongs to
      final orgsUrl = Uri.parse('https://api.github.com/user/orgs');
      final orgsResponse = await http.get(orgsUrl, headers: headers);

      if (orgsResponse.statusCode == 200) {
        final List<dynamic> orgs = jsonDecode(orgsResponse.body);

        // For each organization, fetch its repositories
        for (var org in orgs) {
          final orgLogin = org['login'];
          final orgReposUrl = Uri.parse(
            'https://api.github.com/orgs/$orgLogin/repos?per_page=100',
          );

          final orgReposResponse = await http.get(
            orgReposUrl,
            headers: headers,
          );

          if (orgReposResponse.statusCode == 200) {
            final List<dynamic> orgRepos = jsonDecode(orgReposResponse.body);

            for (var repo in orgRepos) {
              // Only add repos that the user can push to (has write access)
              if (repo['permissions']?['push'] == true) {
                allRepos.add({
                  'name': repo['name'],
                  'full_name': repo['full_name'],
                  'description': repo['description'],
                  'url': repo['html_url'],
                  'stars': repo['stargazers_count'],
                  'forks': repo['forks_count'],
                  'private': repo['private'],
                  'owner': orgLogin,
                  'isOrg': true,
                });
              }
            }
          }
        }
      }

      // Sort all repositories by most recently updated
      allRepos.sort((a, b) {
        // You would need to add 'updated_at' to the repo data to sort by that
        // For now, sort by stars as a proxy for importance
        return (b['stars'] as int).compareTo(a['stars'] as int);
      });

      setState(() {
        _userRepos = allRepos;
        _isLoadingRepos = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingRepos = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e\nMake sure your Personal Access Token has the correct permissions.',
          ),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Fetch only public repositories of a user
  Future<void> _fetchPublicRepositories() async {
    final url = Uri.parse(
      'https://api.github.com/users/$_githubUsername/repos?per_page=100&sort=updated',
    );

    final headers = <String, String>{
      'Accept': 'application/vnd.github.v3+json',
      // Include token auth header if we have token
      if (_githubToken != null && _githubToken!.isNotEmpty)
        'Authorization': 'token $_githubToken',
    };

    try {
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _userRepos =
              data
                  .map(
                    (repo) => {
                      'name': repo['name'],
                      'full_name': repo['full_name'],
                      'description': repo['description'],
                      'url': repo['html_url'],
                      'stars': repo['stargazers_count'],
                      'forks': repo['forks_count'],
                      'private': repo['private'] ?? false,
                      'owner': repo['owner']?['login'] ?? '',
                      'isOrg': false,
                    },
                  )
                  .toList();
          _isLoadingRepos = false;
        });
      } else {
        throw Exception(
          'Failed to load public repositories: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Error fetching repositories: $e');
    }
  }

  // Select a repository to analyze
  void _selectRepository(String repoFullName) {
    _repoUrlController.text = 'https://github.com/$repoFullName';
    _processGitRepository();
  }

  // Logout from GitHub
  void _logoutFromGitHub() {
    setState(() {
      _isLoggedInToGitHub = false;
      _githubUsername = null;
      _githubToken = null;
      _userRepos = [];
    });
  }

  // Fetch public repositories for a given username
  Future<void> _fetchPublicReposByUsername(String username) async {
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a GitHub username'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoadingPublicRepos = true;
      _publicRepos = [];
      _selectedPublicRepo = null;
    });

    try {
      final url = Uri.parse(
        'https://api.github.com/users/$username/repos?per_page=100&sort=updated&type=public',
      );

      final headers = <String, String>{
        'Accept': 'application/vnd.github.v3+json',
        if (_githubToken != null && _githubToken!.isNotEmpty)
          'Authorization': 'token $_githubToken',
      };

      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        if (data.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No public repos found for user: $username'),
              backgroundColor: Colors.orange,
            ),
          );
        }

        setState(() {
          _publicRepos =
              data
                  .map(
                    (repo) => {
                      'name': repo['name'],
                      'full_name': repo['full_name'],
                      'description': repo['description'] ?? 'No description',
                      'url': repo['html_url'],
                      'stars': repo['stargazers_count'] ?? 0,
                      'language': repo['language'] ?? 'Unknown',
                    },
                  )
                  .toList();
          _isLoadingPublicRepos = false;
          _showPublicRepoDropdown = true;
        });
      } else if (response.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User "$username" not found on GitHub'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoadingPublicRepos = false;
        });
      } else {
        throw Exception('Failed to fetch repos: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error fetching repos: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoadingPublicRepos = false;
      });
    }
  }

  // Select a public repo and start analysis
  void _selectPublicRepository(String repoFullName, String repoUrl) {
    _repoUrlController.text = repoUrl;
    setState(() {
      _selectedPublicRepo = repoFullName;
      _showPublicRepoDropdown = false;
    });
    _processGitRepository();
  }

  void handleCodeReviewTap() {
    setState(() {
      selectedPage = 'CodeReview';
    });
  }

  void handleDebugThisCodeForMeTap() {
    setState(() {
      selectedPage = 'Debug';
      fileContent = null;
      codeReviewOutput = null;
    });
    // _pickFile(); - Removed automatic file picker call
  }

  void handleGitRepoReviewTap() {
    setState(() {
      selectedPage = 'GitReview';
      fileContent = null;
      codeReviewOutput = null;
    });
  }

  void handleDashboardTap() {
    setState(() {
      // Change this to explicitly set 'Dashboard' when dashboard is selected
      selectedPage = selectedPage == 'Dashboard' ? '' : 'Dashboard';
      fileContent = null;
      codeReviewOutput = null;
    });
  }

  void handleSendQuery() async {
    if (queryController.text.isEmpty) return;

    setState(() {
      responseMessage = "Generating response...";
    });

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash-lite:generateContent?key=$_geminiApiKey',
    );

    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "text": """
            Act as an expert code reviewer. Analyze the following query:

            "${queryController.text}"

            Provide your analysis in the following structured format:

            ## Summary
            [Brief summary of the query's context and purpose]

            ## Key Insights
            [List any key insights or recommendations]

            ## Improvement Suggestions
            [Provide specific suggestions for improvement]
            """,
            },
          ],
        },
      ],
    });

    try {
      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        setState(() {
          responseMessage = responseText ?? "No analysis could be generated.";
        });
      } else {
        setState(() {
          responseMessage = "Error: ${response.statusCode}\n${response.body}";
        });
      }
    } catch (error) {
      setState(() {
        responseMessage = "Error: $error";
      });
    } finally {
      queryController.clear();
    }
  }

  void handleSendMessage() async {
    if (messageController.text.isEmpty) return;

    final userMessage = messageController.text;
    setState(() {
      chatMessages.add("You: $userMessage");
      messageController.clear();
    });

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash-lite:generateContent?key=$_geminiApiKey',
    );

    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({
      "contents": [
        {
          "parts": [
            {
              "text": """
          If the following message is a general query, respond in a helpful and conversational manner in Markdown format. 
          If it is related to code debugging or you're provided with code snippets, please:
          
          1. Format the code with proper indentation and alignment
          2. Use appropriate syntax highlighting with triple backticks and language name
          3. Organize the response with clear hierarchical headings
          4. Break down complex solutions into step-by-step explanations
          
          For long code blocks:
          - Restructure the code with consistent spacing (4 spaces for indentation)
          - Align related elements vertically (like parameters, assignments, etc.)
          - Add line breaks between logical sections
          - Insert descriptive comments for complex logic
          - Format method chains with one method per line when appropriate
          - For very long lines, break them at logical points
          - Ensure proper bracket alignment and placement
          
          Message: "$userMessage"
          
          Respond appropriately based on the context of the message, focusing on clarity and readability.
          """,
            },
          ],
        },
      ],
    });

    try {
      final response = await http.post(url, headers: headers, body: body);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        setState(() {
          chatMessages.add(
            // Instead of plain text, store a special marker for markdown rendering
            "BotMarkdown: ${responseText ?? "I couldn't generate a response. Please try again."}",
          );
        });
      } else {
        setState(() {
          chatMessages.add("Bot: Error: ${response.statusCode}");
        });
      }
    } catch (error) {
      setState(() {
        chatMessages.add("Bot: Error: $error");
      });
    }
  }

  void handleAtomImageTap() {
    setState(() {
      selectedPage = ''; // Reset to show the transparent image
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine if we're on a mobile device based on screen width
    final bool isMobile = MediaQuery.of(context).size.width < 768;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      // Conditionally show AppBar for mobile only
      appBar:
          isMobile
              ? AppBar(
                backgroundColor: Colors.grey.shade900,
                title: Text(
                  selectedPage == 'GitReview'
                      ? 'GitHub Repository Review'
                      : selectedPage == 'Debug'
                      ? 'Debug Code'
                      : selectedPage == 'CodeReview'
                      ? 'Code Review Chat'
                      : selectedPage.isEmpty
                      ? 'Code Tool'
                      : 'Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationPage(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.settings_outlined, color: Colors.white),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SettingsPage()),
                      );
                    },
                  ),
                ],
              )
              : null,
      body: isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      // Bottom navigation for mobile view
      bottomNavigationBar:
          isMobile
              ? BottomNavigationBar(
                backgroundColor: Colors.grey.shade900,
                selectedItemColor: Colors.blue,
                unselectedItemColor: Colors.grey,
                currentIndex: _getSelectedIndex(), // -1 disables highlight
                type:
                    BottomNavigationBarType
                        .fixed, // Add this to ensure all items are shown
                onTap: (index) {
                  switch (index) {
                    case 0:
                      handleDashboardTap();
                      break;
                    case 1:
                      handleCodeReviewTap();
                      break;
                    case 2:
                      handleDebugThisCodeForMeTap();
                      break;
                    case 3:
                      handleGitRepoReviewTap();
                      break;
                  }
                },
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard),
                    label: 'Dashboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.chat),
                    label: 'Code Chat',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.bug_report),
                    label: 'Debug',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.code),
                    label: 'Git Review',
                  ),
                ],
              )
              : null,
    );
  }

  // Get current index for the bottom navigation bar
  int _getSelectedIndex() {
    switch (selectedPage) {
      case 'Dashboard':
        return 0;
      case 'CodeReview':
        return 1;
      case 'Debug':
        return 2;
      case 'GitReview':
        return 3;
      default:
        // Return 0 instead of -1 to avoid assertion error in BottomNavigationBar
        // and prevent crash. This will highlight Dashboard by default when nothing is selected.
        // If you want no highlight, you must not show the BottomNavigationBar at all,
        // or use a custom widget. Flutter's BottomNavigationBar does not support -1.
        return 0;
    }
  }

  // Desktop Layout with side drawer
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        ResponsiveDrawer(
          onCodeReviewTap: handleCodeReviewTap,
          onDebugThisCodeForMeTap: handleDebugThisCodeForMeTap,
          onGitRepoReviewTap: handleGitRepoReviewTap,
          onDashboardTap: handleDashboardTap,
          onAtomImageTap: handleAtomImageTap,
          selectedPage: selectedPage, // Pass the selected page to drawer
        ),
        Expanded(
          child:
              selectedPage == 'Dashboard'
                  ? _buildDashboard()
                  : selectedPage.isEmpty
                  ? Center(
                    child: Opacity(
                      opacity: 0.5,
                      child: Image.asset(
                        'assets/Image/logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  )
                  : Column(
                    children: [
                      // Header Section
                      Container(
                        padding: const EdgeInsets.all(20.0),
                        color: Colors.grey.shade900,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              selectedPage == 'GitReview'
                                  ? 'GitHub Repository Review'
                                  : selectedPage == 'Debug'
                                  ? 'Debug Code'
                                  : selectedPage == 'CodeReview'
                                  ? 'Code Review Chat'
                                  : '',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.notifications_outlined,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => NotificationPage(),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.settings_outlined,
                                    color: Colors.white,
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => SettingsPage(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Main Content
                      Expanded(
                        child:
                            selectedPage == 'GitReview'
                                ? _buildGitHubUI()
                                : selectedPage == 'Debug'
                                ? _buildDebugPage()
                                : selectedPage == 'CodeReview'
                                ? _buildChatbotUI()
                                : Container(), // Empty for any other case
                      ),
                    ],
                  ),
        ),
      ],
    );
  }

  // Mobile Layout without side drawer
  Widget _buildMobileLayout() {
    // Show dashboard directly when selectedPage is empty
    return selectedPage.isEmpty
        ? _buildMobileDashboard()
        : selectedPage == 'GitReview'
        ? _buildMobileGitHubUI()
        : selectedPage == 'Debug'
        ? _buildMobileDebugPage()
        : selectedPage == 'CodeReview'
        ? _buildChatbotUI() // Chatbot UI works well on mobile already
        : selectedPage == 'Dashboard'
        ? _buildMobileDashboard()
        : Center(
          child: Opacity(
            opacity: 0.5,
            child: Image.asset('assets/Image/logo.png', fit: BoxFit.contain),
          ),
        );
  }

  // Mobile version of GitHub UI
  Widget _buildMobileGitHubUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _repoUrlController,
            decoration: InputDecoration(
              labelText: 'GitHub Repository URL',
              labelStyle: TextStyle(color: Colors.white),
              hintText: 'https://github.com/username/repository',
              hintStyle: TextStyle(color: Colors.grey),
              filled: true,
              fillColor: Colors.grey.shade800,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(Icons.link, color: Colors.grey),
              suffixIcon: IconButton(
                icon: Icon(Icons.clear, color: Colors.grey),
                onPressed: () => _repoUrlController.clear(),
              ),
            ),
            style: TextStyle(color: Colors.white),
          ),
          SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.cloud_download),
                  label: Text('Analyze Repository'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  ),
                  onPressed: _isProcessingRepo ? null : _processGitRepository,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: ElevatedButton.icon(
                  icon: Icon(
                    _isLoggedInToGitHub ? Icons.logout : Icons.login,
                    size: 16,
                  ),
                  label: Text('GitHub', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.shade800,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 15),
                  ),
                  onPressed:
                      _isLoggedInToGitHub
                          ? _logoutFromGitHub
                          : _showGitHubLoginDialog,
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Public Repository Lookup Section (Mobile)
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search Public Repositories',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: _publicRepoUsernameController,
                  decoration: InputDecoration(
                    labelText: 'GitHub Username',
                    labelStyle: TextStyle(color: Colors.white, fontSize: 13),
                    hintText: 'Enter username',
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                    filled: true,
                    fillColor: Colors.grey.shade700,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(
                      Icons.person,
                      color: Colors.grey,
                      size: 20,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey, size: 18),
                      onPressed: () => _publicRepoUsernameController.clear(),
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.search, size: 18),
                    label: Text('Search Repos', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed:
                        _isLoadingPublicRepos
                            ? null
                            : () => _fetchPublicReposByUsername(
                              _publicRepoUsernameController.text,
                            ),
                  ),
                ),
                SizedBox(height: 10),
                // Public Repos List (Mobile)
                if (_isLoadingPublicRepos)
                  Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(
                        Colors.purple.shade300,
                      ),
                    ),
                  )
                else if (_publicRepos.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Found ${_publicRepos.length} repositor${_publicRepos.length > 1 ? 'ies' : 'y'}',
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        constraints: BoxConstraints(maxHeight: 250),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.purple.withOpacity(0.3),
                          ),
                        ),
                        child: ListView.builder(
                          itemCount: _publicRepos.length,
                          itemBuilder: (context, index) {
                            final repo = _publicRepos[index];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              title: Text(
                                repo['name'],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                repo['description'] ?? 'No description',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: Icon(
                                Icons.arrow_forward,
                                color: Colors.purple.shade300,
                                size: 18,
                              ),
                              onTap:
                                  () => _selectPublicRepository(
                                    repo['full_name'],
                                    repo['url'],
                                  ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                else if (_showPublicRepoDropdown)
                  Text(
                    'No repositories found',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // User repositories section (when logged in)
          if (_isLoggedInToGitHub && _userRepos.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 20),
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Repositories (tap to select)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 15),
                  Container(
                    height: 200,
                    child: ListView.builder(
                      itemCount: _userRepos.length,
                      itemBuilder: (context, index) {
                        final repo = _userRepos[index];
                        return ListTile(
                          title: Row(
                            children: [
                              Text(
                                repo['name'],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 8),
                              if (repo['private'] == true)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade700,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Private',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              if (repo['isOrg'] == true)
                                Container(
                                  margin: EdgeInsets.only(left: 4),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade800,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Org',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (repo['owner'] != _githubUsername &&
                                  !repo['isOrg'])
                                Padding(
                                  padding: EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    'Forked from: ${repo['owner']}',
                                    style: TextStyle(
                                      color: Colors.blue.shade300,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              Text(
                                repo['description'] ?? 'No description',
                                style: TextStyle(color: Colors.grey.shade400),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              Text(
                                ' ${repo['stars']} ',
                                style: TextStyle(color: Colors.white),
                              ),
                              Icon(
                                Icons.fork_right,
                                color: Colors.blue,
                                size: 16,
                              ),
                              Text(
                                ' ${repo['forks']}',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                          onTap: () => _selectRepository(repo['full_name']),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          if (_isLoggedInToGitHub && _isLoadingRepos)
            Container(
              margin: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 10),
                    Text(
                      'Loading repositories...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          // Repository processing status
          if (_isProcessingRepo || _repoProcessStatus != null)
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  if (_isProcessingRepo)
                    Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  SizedBox(height: 10),
                  Text(
                    _repoProcessStatus ?? '',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),

          if (_repoName != null && !_isProcessingRepo)
            Container(
              margin: EdgeInsets.symmetric(vertical: 15),
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repository: $_repoName',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Files: ${_repoFiles.length}',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 15),
                  ElevatedButton.icon(
                    icon: Icon(Icons.analytics),
                    label: Text('Analyze Entire Repository'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      minimumSize: Size(double.infinity, 50),
                    ),
                    onPressed: _analyzeRepositoryWithGemini,
                  ),
                  SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _repoName = null;
                        _repoFiles = [];
                        _currentFileIndex = -1;
                        fileContent = null;
                        codeReviewOutput = null;
                        _repoProcessStatus = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      minimumSize: Size(double.infinity, 50),
                    ),
                    child: Text(
                      'Clear Repository',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          // Files and analysis section - no longer in an Expanded widget
          if (_repoFiles.isNotEmpty)
            Column(
              children: [
                // Files list with horizontal scrolling
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade900,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _repoFiles.length,
                    itemBuilder: (context, index) {
                      return InkWell(
                        onTap: () => _loadRepositoryFile(index),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color:
                                    index == _currentFileIndex
                                        ? Colors.blue
                                        : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            _repoFiles[index].split('/').last,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  index == _currentFileIndex
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                SizedBox(height: 16),

                // Code and Analysis tabs with fixed height instead of Expanded
                Container(
                  height: 400, // Fixed height for content area
                  child: DefaultTabController(
                    length: 2,
                    initialIndex: _mobileRepoTabController?.index ?? 0,
                    child: Builder(
                      builder: (context) {
                        // Attach controller if available
                        if (_mobileRepoTabController != null) {
                          DefaultTabController.of(
                            context,
                          ).animation?.addListener(() {});
                          DefaultTabController.of(context).index =
                              _mobileRepoTabController!.index;
                        }
                        return Column(
                          children: [
                            TabBar(
                              controller: _mobileRepoTabController,
                              tabs: [Tab(text: 'Code'), Tab(text: 'Analysis')],
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.grey,
                              indicatorColor: Colors.blue,
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _mobileRepoTabController,
                                children: [
                                  // Code Tab
                                  Container(
                                    padding: EdgeInsets.all(15),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade900,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: SingleChildScrollView(
                                      child:
                                          fileContent != null
                                              ? SelectableText(
                                                fileContent!,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontFamily: 'Courier',
                                                  fontSize: 14,
                                                ),
                                              )
                                              : Center(
                                                child: Text(
                                                  'Select a file to view its content',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                    ),
                                  ),

                                  // Analysis Tab
                                  Container(
                                    padding: EdgeInsets.all(15),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade900,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: SingleChildScrollView(
                                      child:
                                          codeReviewOutput != null
                                              ? isTyping
                                                  ? AnimatedTextKit(
                                                    animatedTexts: [
                                                      TyperAnimatedText(
                                                        codeReviewOutput!,
                                                        textStyle: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14,
                                                        ),
                                                        speed: Duration(
                                                          milliseconds: 10,
                                                        ),
                                                      ),
                                                    ],
                                                    isRepeatingAnimation: false,
                                                    onFinished: () {
                                                      setState(() {
                                                        isTyping = false;
                                                      });
                                                    },
                                                  )
                                                  : MarkdownBody(
                                                    data: codeReviewOutput!,
                                                    styleSheet: MarkdownStyleSheet(
                                                      p: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 14,
                                                      ),
                                                      h1: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      h2: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      code: TextStyle(
                                                        color: Colors.lightBlue,
                                                        fontSize: 14,
                                                        backgroundColor:
                                                            Colors.black38,
                                                      ),
                                                      codeblockPadding:
                                                          EdgeInsets.all(8),
                                                      codeblockDecoration:
                                                          BoxDecoration(
                                                            color:
                                                                Colors.black45,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                    ),
                                                  )
                                              : Center(
                                                child: Text(
                                                  'Analysis will appear here',
                                                  style: TextStyle(
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // Mobile version of Debug page
  Widget _buildMobileDebugPage() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Improved file selection button with better feedback
          ElevatedButton(
            onPressed: () async {
              await _pickFile();
              // Force UI refresh after file is picked
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              minimumSize: Size(double.infinity, 50),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.attach_file, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Select File to Debug',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Instruction text instead of dropdown
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade300),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Files will be analyzed for readability, errors, security risks, and performance issues',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20),

          // Conditional display based on file content
          if (fileContent != null)
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [Tab(text: 'Code'), Tab(text: 'Analysis')],
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.blue,
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          // Code Tab
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade700),
                            ),
                            padding: EdgeInsets.all(15),
                            margin: EdgeInsets.only(top: 10),
                            child: SingleChildScrollView(
                              child: SelectableText(
                                fileContent!,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Courier',
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),

                          // Analysis Tab
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.shade700),
                            ),
                            padding: EdgeInsets.all(15),
                            margin: EdgeInsets.only(top: 10),
                            child: SingleChildScrollView(
                              child:
                                  codeReviewOutput != null
                                      ? isTyping
                                          ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.blue,
                                                        ),
                                                  ),
                                                  SizedBox(width: 10),
                                                  Text(
                                                    'Analyzing code...',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              SizedBox(height: 16),
                                              AnimatedTextKit(
                                                animatedTexts: [
                                                  TyperAnimatedText(
                                                    codeReviewOutput!,
                                                    textStyle: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 14,
                                                    ),
                                                    speed: Duration(
                                                      milliseconds: 10,
                                                    ),
                                                  ),
                                                ],
                                                isRepeatingAnimation: false,
                                                onFinished: () {
                                                  setState(() {
                                                    isTyping = false;
                                                  });
                                                },
                                              ),
                                            ],
                                          )
                                          : MarkdownBody(
                                            data: codeReviewOutput!,
                                            styleSheet: MarkdownStyleSheet(
                                              p: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                              h1: TextStyle(
                                                color: Colors.white,
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              h2: TextStyle(
                                                color: Colors.white,
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              code: TextStyle(
                                                color: Colors.lightBlue,
                                                fontSize: 14,
                                                backgroundColor: Colors.black38,
                                              ),
                                              codeblockPadding: EdgeInsets.all(
                                                8,
                                              ),
                                              codeblockDecoration:
                                                  BoxDecoration(
                                                    color: Colors.black45,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                            ),
                                          )
                                      : Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.sentiment_neutral,
                                              color: Colors.grey.shade600,
                                              size: 48,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'Select a file to analyze',
                                              style: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.upload_file,
                        size: 70,
                        color: Colors.grey.shade600,
                      ),
                      SizedBox(height: 20),
                      Text(
                        'No file selected',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Tap the button above to select a code file for analysis',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Mobile version of Dashboard
  Widget _buildMobileDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Statistics Cards for mobile (stacked)
          _buildMobileStatCard(
            'Code Reviews',
            '24',
            Icons.code,
            Colors.blue.shade700,
          ),
          SizedBox(height: 12),
          _buildMobileStatCard(
            'Debug Sessions',
            '12',
            Icons.bug_report,
            Colors.green.shade700,
          ),
          SizedBox(height: 12),
          _buildMobileStatCard(
            'Git Reviews',
            '8',
            Icons.code,
            Colors.purple.shade700,
          ),
          SizedBox(height: 24),

          // Recent Activity Section
          Text(
            'Recent Activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          _buildRecentActivityList(),
        ],
      ),
    );
  }

  Widget _buildGitHubUI() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Repository URL input section with GitHub button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _repoUrlController,
                  decoration: InputDecoration(
                    labelText: 'GitHub Repository URL',
                    labelStyle: TextStyle(color: Colors.white),
                    hintText: 'https://github.com/username/repository',
                    hintStyle: TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey.shade800,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(Icons.link, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey),
                      onPressed: () => _repoUrlController.clear(),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
              SizedBox(width: 10),
              ElevatedButton.icon(
                icon: Icon(Icons.cloud_download),
                label: Text('Analyze Repository'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                onPressed: _isProcessingRepo ? null : _processGitRepository,
              ),
              SizedBox(width: 10),
              ElevatedButton.icon(
                icon: Icon(_isLoggedInToGitHub ? Icons.logout : Icons.login),
                label: Text(
                  _isLoggedInToGitHub
                      ? 'GitHub ($_githubUsername)'
                      : 'GitHub Login',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade800,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
                onPressed:
                    _isLoggedInToGitHub
                        ? _logoutFromGitHub
                        : _showGitHubLoginDialog,
              ),
            ],
          ),

          SizedBox(height: 20),

          // Public Repository Lookup Section
          Container(
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search Public Repositories',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _publicRepoUsernameController,
                        decoration: InputDecoration(
                          labelText: 'GitHub Username',
                          labelStyle: TextStyle(color: Colors.white),
                          hintText: 'Enter username (e.g., flutter)',
                          hintStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Colors.grey.shade700,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          prefixIcon: Icon(Icons.person, color: Colors.grey),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey),
                            onPressed:
                                () => _publicRepoUsernameController.clear(),
                          ),
                        ),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton.icon(
                      icon: Icon(Icons.search),
                      label: Text('Search Repos'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 15,
                        ),
                      ),
                      onPressed:
                          _isLoadingPublicRepos
                              ? null
                              : () => _fetchPublicReposByUsername(
                                _publicRepoUsernameController.text,
                              ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                // Public Repos Dropdown
                if (_isLoadingPublicRepos)
                  Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation(
                        Colors.purple.shade300,
                      ),
                    ),
                  )
                else if (_publicRepos.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Found ${_publicRepos.length} public repositor${_publicRepos.length > 1 ? 'ies' : 'y'}',
                        style: TextStyle(
                          color: Colors.grey.shade300,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        constraints: BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.purple.withOpacity(0.3),
                          ),
                        ),
                        child: ListView.builder(
                          itemCount: _publicRepos.length,
                          itemBuilder: (context, index) {
                            final repo = _publicRepos[index];
                            return ListTile(
                              title: Text(
                                repo['name'],
                                style: TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                repo['description'] ?? 'No description',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey.shade400),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star,
                                    size: 16,
                                    color: Colors.amber,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    repo['stars'].toString(),
                                    style: TextStyle(
                                      color: Colors.grey.shade300,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  if (repo['language'] != null &&
                                      repo['language'] != 'Unknown')
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        repo['language'],
                                        style: TextStyle(
                                          color: Colors.purple.shade300,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              onTap:
                                  () => _selectPublicRepository(
                                    repo['full_name'],
                                    repo['url'],
                                  ),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                else if (_showPublicRepoDropdown)
                  Text(
                    'No repositories found',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),

          SizedBox(height: 20),

          // User repositories section (when logged in)
          if (_isLoggedInToGitHub && _userRepos.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 20),
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your GitHub Repositories',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 15),
                  Container(
                    height: 200,
                    child: ListView.builder(
                      itemCount: _userRepos.length,
                      itemBuilder: (context, index) {
                        final repo = _userRepos[index];
                        return ListTile(
                          title: Row(
                            children: [
                              Text(
                                repo['name'],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 8),
                              if (repo['private'] == true)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade700,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Private',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              if (repo['isOrg'] == true)
                                Container(
                                  margin: EdgeInsets.only(left: 4),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.shade800,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Org',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (repo['owner'] != _githubUsername &&
                                  !repo['isOrg'])
                                Padding(
                                  padding: EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    'Forked from: ${repo['owner']}',
                                    style: TextStyle(
                                      color: Colors.blue.shade300,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              Text(
                                repo['description'] ?? 'No description',
                                style: TextStyle(color: Colors.grey.shade400),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 16),
                              Text(
                                ' ${repo['stars']} ',
                                style: TextStyle(color: Colors.white),
                              ),
                              Icon(
                                Icons.fork_right,
                                color: Colors.blue,
                                size: 16,
                              ),
                              Text(
                                ' ${repo['forks']}',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                          onTap: () => _selectRepository(repo['full_name']),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          if (_isLoggedInToGitHub && _isLoadingRepos)
            Container(
              margin: EdgeInsets.only(top: 20),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 10),
                    Text(
                      'Loading repositories...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(height: 20),

          // Repository processing status
          if (_isProcessingRepo || _repoProcessStatus != null)
            Container(
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  if (_isProcessingRepo)
                    Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  SizedBox(height: 10),
                  Text(
                    _repoProcessStatus ?? '',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),

          // Repository info section
          if (_repoName != null && !_isProcessingRepo)
            Container(
              margin: EdgeInsets.symmetric(vertical: 15),
              padding: EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Repository: $_repoName',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Files: ${_repoFiles.length}',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: Icon(Icons.analytics),
                        label: Text('Analyze Entire Repository'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onPressed: _analyzeRepositoryWithGemini,
                      ),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _repoName = null;
                            _repoFiles = [];
                            _currentFileIndex = -1;
                            fileContent = null;
                            codeReviewOutput = null;
                            _repoProcessStatus = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          'Clear Repository',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Main content area (files list + code + analysis)
          if (_repoFiles.isNotEmpty)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Files list
                  Container(
                    width: 300,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade700),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(
                            'Repository Files:',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Divider(color: Colors.grey.shade700, height: 1),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _repoFiles.length,
                            itemBuilder: (context, index) {
                              return ListTile(
                                leading: Icon(
                                  Icons.insert_drive_file,
                                  color: Colors.grey.shade300,
                                ),
                                title: Text(
                                  _repoFiles[index],
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight:
                                        index == _currentFileIndex
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                  ),
                                ),
                                selected: index == _currentFileIndex,
                                selectedTileColor: Colors.blue.withOpacity(0.2),
                                onTap: () => _loadRepositoryFile(index),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(width: 16),

                  // Code and analysis section
                  Expanded(
                    child: DefaultTabController(
                      length: 2,
                      initialIndex: _repoTabController?.index ?? 0,
                      child: Builder(
                        builder: (context) {
                          // Attach controller if available
                          if (_repoTabController != null) {
                            DefaultTabController.of(
                              context,
                            ).animation?.addListener(() {});
                            DefaultTabController.of(context).index =
                                _repoTabController!.index;
                          }
                          return Column(
                            children: [
                              TabBar(
                                controller: _repoTabController,
                                tabs: [
                                  Tab(text: 'Code'),
                                  Tab(text: 'Analysis'),
                                ],
                                labelColor: Colors.white,
                                unselectedLabelColor: Colors.grey,
                                indicatorColor: Colors.blue,
                              ),
                              Expanded(
                                child: TabBarView(
                                  controller: _repoTabController,
                                  children: [
                                    // Code Tab
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade900,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      padding: EdgeInsets.all(15),
                                      child: SingleChildScrollView(
                                        child:
                                            fileContent != null
                                                ? SelectableText(
                                                  fileContent!,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontFamily: 'Courier',
                                                    fontSize: 14,
                                                  ),
                                                )
                                                : Center(
                                                  child: Text(
                                                    'Select a file from the list to see its content',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                      ),
                                    ),

                                    // Analysis Tab
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade900,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      padding: EdgeInsets.all(15),
                                      child: SingleChildScrollView(
                                        child:
                                            codeReviewOutput != null
                                                ? isTyping
                                                    ? AnimatedTextKit(
                                                      animatedTexts: [
                                                        TyperAnimatedText(
                                                          codeReviewOutput!,
                                                          textStyle: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 14,
                                                          ),
                                                          speed: Duration(
                                                            milliseconds: 10,
                                                          ),
                                                        ),
                                                      ],
                                                      isRepeatingAnimation:
                                                          false,
                                                      onFinished: () {
                                                        setState(() {
                                                          isTyping = false;
                                                        });
                                                      },
                                                    )
                                                    : MarkdownBody(
                                                      data: codeReviewOutput!,
                                                      styleSheet: MarkdownStyleSheet(
                                                        p: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 14,
                                                        ),
                                                        h1: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        h2: TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                        code: TextStyle(
                                                          color:
                                                              Colors.lightBlue,
                                                          fontSize: 14,
                                                          backgroundColor:
                                                              Colors.black38,
                                                        ),
                                                        codeblockPadding:
                                                            EdgeInsets.all(8),
                                                        codeblockDecoration:
                                                            BoxDecoration(
                                                              color:
                                                                  Colors
                                                                      .black45,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                      ),
                                                    )
                                                : Center(
                                                  child: Text(
                                                    'Analysis will appear here',
                                                    style: TextStyle(
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDebugPage() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _pickFile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            child: Text(
              'Select File to Debug',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          SizedBox(height: 20),
          if (fileContent != null)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      padding: EdgeInsets.all(15),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          fileContent!,
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Courier',
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 20),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade700),
                      ),
                      padding: EdgeInsets.all(15),
                      child: SingleChildScrollView(
                        child:
                            codeReviewOutput != null
                                ? MarkdownBody(
                                  data: codeReviewOutput!,
                                  styleSheet: MarkdownStyleSheet(
                                    p: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                    h1: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    h2: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    code: TextStyle(
                                      color: Colors.lightBlue,
                                      fontSize: 14,
                                      backgroundColor: Colors.black38,
                                    ),
                                    codeblockPadding: EdgeInsets.all(8),
                                    codeblockDecoration: BoxDecoration(
                                      color: Colors.black45,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                )
                                : Center(
                                  child: Text(
                                    'Debug output will appear here',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.code, size: 60, color: Colors.grey.shade600),
                      SizedBox(height: 20),
                      Text(
                        'No file selected',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Please select a code file to debug',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChatbotUI() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: chatMessages.length,
              itemBuilder: (context, index) {
                final msg = chatMessages[index];
                final isUser = msg.startsWith("You:");
                final isMarkdown = msg.startsWith("BotMarkdown:");
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(12.0),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isUser
                                ? Colors.blue.shade700
                                : Colors.grey.shade700,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          isMarkdown
                              ? MarkdownBody(
                                data: msg.replaceFirst("BotMarkdown: ", ""),
                                styleSheet: MarkdownStyleSheet(
                                  p: TextStyle(color: Colors.white),
                                  code: TextStyle(
                                    color: Colors.lightBlue,
                                    fontSize: 14,
                                    backgroundColor: Colors.black38,
                                  ),
                                  codeblockPadding: EdgeInsets.all(8),
                                  codeblockDecoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              )
                              : Text(
                                msg,
                                style: TextStyle(color: Colors.white),
                              ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Chat Input Section
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    filled: true,
                    fillColor: Colors.grey.shade900,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: handleSendMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Icon(Icons.send, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Statistics Cards
          Row(
            children: [
              _buildStatCard(
                'Code Reviews',
                '24',
                Icons.code,
                Colors.blue.shade700,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                'Debug Sessions',
                '12',
                Icons.bug_report,
                Colors.green.shade700,
              ),
              const SizedBox(width: 16),
              _buildStatCard(
                'Git Reviews',
                '8',
                Icons.code,
                Colors.purple.shade700,
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Recent Activity Section
          Text(
            'Recent Activity',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          _buildRecentActivityList(),
        ],
      ),
    );
  }

  // Mobile stat card for dashboard
  Widget _buildMobileStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.grey.shade300, fontSize: 16),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Desktop stat card for dashboard
  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.5), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 16),
                ),
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Recent activity list for dashboard
  Widget _buildRecentActivityList() {
    final activities = [
      {
        'icon': Icons.code,
        'title': 'Code Review',
        'description': 'Reviewed React component library',
        'time': '2 hours ago',
        'color': Colors.blue,
      },
      {
        'icon': Icons.bug_report,
        'title': 'Debug Session',
        'description': 'Fixed memory leak in Python script',
        'time': '4 hours ago',
        'color': Colors.green,
      },
      {
        'icon': Icons.code,
        'title': 'Git Repository Review',
        'description': 'Analyzed flutter_app_template repository',
        'time': 'Yesterday',
        'color': Colors.purple,
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: activities.length,
        separatorBuilder:
            (context, index) => Divider(color: Colors.grey.shade700, height: 1),
        itemBuilder: (context, index) {
          final activity = activities[index];
          return ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (activity['color'] as Color).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                activity['icon'] as IconData,
                color: activity['color'] as Color,
              ),
            ),
            title: Text(
              activity['title'] as String,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              activity['description'] as String,
              style: TextStyle(color: Colors.grey.shade400),
            ),
            trailing: Text(
              activity['time'] as String,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}
