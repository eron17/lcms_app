// lib/presentation/courses/file_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/file_downloader.dart';
import 'dart:io';
import '../../shared/widgets/pressable_scale.dart';

class FileViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;
  final bool isLocal;
  final bool isStudent;

  const FileViewerScreen({
    super.key,
    required this.url,
    required this.fileName,
    this.isLocal = false,
    this.isStudent = true,
  });

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  // ─── Video State ─────────────────────────────────────────
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _videoInitialized = false;
  String? _videoError;

  // ─── PDF State ────────────────────────────────────────────
  final PdfViewerController _pdfController = PdfViewerController();
  bool _pdfLoaded = false;
  String? _pdfError;

  // ─── Office Doc State (Word / PPT / Excel via Google Docs Viewer) ──
  WebViewController? _officeController;
  bool _officeLoading = true;
  bool _officeError = false;

  // ─── File Type ────────────────────────────────────────────
  late String _fileType;

  @override
  void initState() {
    super.initState();
    _fileType = _getFileType(widget.fileName);
    if (_fileType == 'video') {
      _initVideoPlayer();
    } else if (_fileType == 'office') {
      if (widget.isLocal) {
        // Google Docs Viewer needs a public URL — it can't reach a path
        // on-device, so local Office docs are handed to the device's
        // installed Office app instead.
        WidgetsBinding.instance.addPostFrameCallback((_) => _openLocalFile());
      } else {
        _initOfficeViewer();
      }
    }
  }

  Future<void> _openLocalFile() async {
    try {
      final result = await OpenFilex.open(widget.url);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open file. Make sure you have an Office app '
              'installed (WPS Office or Microsoft Office).',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Open local file error: $e');
    }
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return 'pdf';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'image';
    if (['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'].contains(ext)) {
      return 'office';
    }
    return 'unknown';
  }

  String get _fileExtension => widget.fileName.split('.').last.toLowerCase();

  Color _fileTypeColor() {
    switch (_fileExtension) {
      case 'pdf':
        return const Color(0xFFFF4D4D);
      case 'doc':
      case 'docx':
        return const Color(0xFF2B579A);
      case 'ppt':
      case 'pptx':
        return const Color(0xFFD24726);
      case 'xls':
      case 'xlsx':
        return const Color(0xFF217346);
      default:
        return AppColors.primary;
    }
  }

  String _fileTypeLabel() {
    switch (_fileExtension) {
      case 'pdf':
        return 'PDF';
      case 'doc':
      case 'docx':
        return 'DOC';
      case 'ppt':
      case 'pptx':
        return 'PPT';
      case 'xls':
      case 'xlsx':
        return 'XLS';
      default:
        return _fileExtension.toUpperCase();
    }
  }

  void _initOfficeViewer() {
    // Strip any existing query parameters from the Supabase URL before
    // passing to Google Docs Viewer to avoid double-encoding issues.
    final cleanUrl = widget.url.split('?').first;
    final viewerUrl =
        'https://docs.google.com/viewer?url=${Uri.encodeComponent(cleanUrl)}&embedded=true';
    _officeController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            // Keep navigation inside Google Docs Viewer. Without this, a
            // doc it can't render (common for some .xlsx files) can
            // navigate to the raw Supabase file URL, which Android then
            // hands off to a system app instead of showing it in-app.
            if (request.url.startsWith('https://docs.google.com')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _officeLoading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _officeLoading = false;
                _officeError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(viewerUrl));
  }

  Future<void> _initVideoPlayer() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      _videoController = controller;
      await controller.initialize();
      _chewieController = ChewieController(
        videoPlayerController: controller,
        autoPlay: false,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: Colors.grey,
          bufferedColor: AppColors.primary.withValues(alpha: 0.3),
        ),
      );
      if (mounted) setState(() => _videoInitialized = true);
    } catch (e) {
      debugPrint('Video init error: $e');
      if (mounted) {
        setState(
          () => _videoError =
              'The video may be corrupted, unavailable, or the '
              'connection was interrupted.',
        );
      }
    }
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    _pdfController.dispose();
    if (_officeController != null) {
      WebViewCookieManager().clearCookies();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fileType == 'video' ? Colors.black : context.bgColor,
      appBar: AppBar(
        backgroundColor: _fileType == 'video'
            ? Colors.black
            : context.cardColor,
        foregroundColor: _fileType == 'video'
            ? Colors.white
            : context.textPrimary,
        elevation: 0,
        leadingWidth: 70,
        leading: Center(
          child: PressableScale(
            onPressed: () => Navigator.pop(context),
            scaleFactor: 1.0, // Opacity only
            opacityFactor: 0.5,
            child: Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: _fileType == 'video'
                    ? Colors.white
                    : context.textPrimary,
                size: 25,
              ),
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _fileType == 'video'
                    ? Colors.white
                    : context.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _fileType == 'office' ? _fileTypeLabel() : _fileType.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: _fileType == 'office' ? FontWeight.w700 : null,
                color: _fileType == 'video'
                    ? Colors.white54
                    : _fileType == 'office'
                    ? _fileTypeColor()
                    : context.textSecondary,
              ),
            ),
          ],
        ),
        // Toolbar actions
        actions: [
          // PDF zoom controls
          if (_fileType == 'pdf' && _pdfLoaded) ...[
            IconButton(
              icon: Icon(Icons.zoom_in, color: context.textPrimary),
              onPressed: () => _pdfController.zoomLevel =
                  _pdfController.zoomLevel + 0.25,
            ),
            IconButton(
              icon: Icon(Icons.zoom_out, color: context.textPrimary),
              onPressed: () => _pdfController.zoomLevel =
                  (_pdfController.zoomLevel - 0.25).clamp(0.5, 5.0),
            ),
          ],
          // Download
          if (!widget.isLocal && widget.isStudent)
            IconButton(
              icon: Icon(
                Icons.download_rounded,
                color: _fileType == 'video' ? Colors.white : AppColors.primary,
              ),
              tooltip: 'Download',
              onPressed: () => FileDownloader.downloadAndOpen(
                context: context,
                url: widget.url,
                fileName: widget.fileName,
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_fileType) {
      case 'pdf':
        return _buildPdfViewer();
      case 'video':
        return _buildVideoPlayer();
      case 'image':
        return _buildImageViewer();
      case 'office':
        return widget.isLocal ? _buildLocalOfficeFile() : _buildOfficeViewer();
      default:
        return _buildUnsupportedFile();
    }
  }

  // ─── Local Office Doc (opened via device Office app) ───────
  Widget _buildLocalOfficeFile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.open_in_new_rounded,
              size: 64,
              color: context.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Opening in your Office app...',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If nothing happened, tap below to try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openLocalFile,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text(
                'Open File',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(String message) {
    return Container(
      color: context.bgColor,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Office Doc Viewer (Word / PPT / Excel) ────────────────
  Widget _buildOfficeViewer() {
    final officeController = _officeController;
    if (officeController == null) return _buildUnsupportedFile();
    return Stack(
      children: [
        WebViewWidget(controller: officeController),
        if (_officeLoading) _buildLoadingState('Loading document...'),
        if (_officeError && !_officeLoading)
          Container(
            color: context.bgColor,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.file_present_rounded,
                      size: 64,
                      color: context.textHint,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Preview not available',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.isDark
                            ? Colors.white
                            : const Color(0xFF0D1B4B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Google Docs Viewer could not load this file. '
                      "Download it to view offline using your device's "
                      'Office app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textSecondary,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _officeLoading = true;
                          _officeError = false;
                        });
                        _officeController?.reload();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Retry',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (widget.isStudent) ...[
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: () => FileDownloader.downloadAndOpen(
                          context: context,
                          url: widget.url,
                          fileName: widget.fileName,
                        ),
                        icon: const Icon(
                          Icons.download_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        label: const Text(
                          'Download instead',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── PDF Viewer ───────────────────────────────────────────
  Widget _buildPdfViewer() {
    final pdfWidget = widget.isLocal
        ? SfPdfViewer.file(
            File(widget.url),
            controller: _pdfController,
            onDocumentLoaded: (details) {
              if (mounted) setState(() => _pdfLoaded = true);
            },
            onDocumentLoadFailed: (details) {
              debugPrint('PDF load error: ${details.description}');
              if (mounted) {
                setState(
                  () => _pdfError =
                      'The file may be corrupted, unavailable, or the '
                      'connection was interrupted.',
                );
              }
            },
            pageLayoutMode: PdfPageLayoutMode.continuous,
            scrollDirection: PdfScrollDirection.vertical,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            canShowPaginationDialog: true,
          )
        : SfPdfViewer.network(
            widget.url,
            controller: _pdfController,
            onDocumentLoaded: (details) {
              if (mounted) setState(() => _pdfLoaded = true);
            },
            onDocumentLoadFailed: (details) {
              debugPrint('PDF load error: ${details.description}');
              if (mounted) {
                setState(
                  () => _pdfError =
                      'The file may be corrupted, unavailable, or the '
                      'connection was interrupted.',
                );
              }
            },
            pageLayoutMode: PdfPageLayoutMode.continuous,
            scrollDirection: PdfScrollDirection.vertical,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            canShowPaginationDialog: true,
          );

    final pdfError = _pdfError;
    return Stack(
      children: [
        pdfWidget,

        if (!_pdfLoaded && pdfError == null) _buildLoadingState('Loading PDF...'),

        // Error state
        if (pdfError != null)
          Container(
            color: context.bgColor,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load PDF',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      pdfError,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: context.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _pdfError = null;
                          _pdfLoaded = false;
                        });
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text(
                        'Retry',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Video Player ─────────────────────────────────────────
  Widget _buildVideoPlayer() {
    final videoError = _videoError;
    if (videoError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              const Text(
                'Failed to load video',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                videoError,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.white54,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_videoInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return Center(child: Chewie(controller: _chewieController!));
  }

  // ─── Image Viewer ─────────────────────────────────────────
  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: Image.network(
          widget.url,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 64,
                color: context.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load image',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Unsupported File ─────────────────────────────────────
  Widget _buildUnsupportedFile() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: context.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'Cannot preview this file',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This file type is not supported for in-app preview.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: context.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
