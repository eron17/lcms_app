// lib/presentation/courses/file_viewer_screen.dart
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/theme_extensions.dart';
import 'dart:io';

class FileViewerScreen extends StatefulWidget {
  final String url;
  final String fileName;
  final bool isLocal;

  const FileViewerScreen({
    super.key,
    required this.url,
    required this.fileName,
    this.isLocal = false,
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

  // ─── File Type ────────────────────────────────────────────
  late String _fileType;

  @override
  void initState() {
    super.initState();
    _fileType = _getFileType(widget.fileName);
    if (_fileType == 'video') {
      _initVideoPlayer();
    }
  }

  String _getFileType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['pdf'].contains(ext)) return 'pdf';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return 'video';
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) return 'image';
    return 'unknown';
  }

  Future<void> _initVideoPlayer() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      await _videoController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
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
      if (mounted) setState(() => _videoError = e.toString());
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _pdfController.dispose();
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
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _fileType == 'video'
                  ? Colors.white.withValues(alpha: 0.1)
                  : context.bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _fileType == 'video'
                    ? Colors.white.withValues(alpha: 0.2)
                    : context.borderColor,
              ),
            ),
            child: Icon(
              Icons.arrow_back,
              color: _fileType == 'video' ? Colors.white : context.textPrimary,
              size: 20,
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
                color: _fileType == 'video' ? Colors.white : context.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _fileType.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                color: _fileType == 'video'
                    ? Colors.white54
                    : context.textSecondary,
              ),
            ),
          ],
        ),
        // PDF toolbar actions
        actions: _fileType == 'pdf' && _pdfLoaded
            ? [
                IconButton(
                  icon: Icon(Icons.zoom_in, color: context.textPrimary),
                  onPressed: () => _pdfController.zoomLevel = _pdfController.zoomLevel + 0.25,
                ),
                IconButton(
                  icon: Icon(Icons.zoom_out, color: context.textPrimary),
                  onPressed: () => _pdfController.zoomLevel =
                      (_pdfController.zoomLevel - 0.25).clamp(0.5, 5.0),
                ),
              ]
            : null,
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
      default:
        return _buildUnsupportedFile();
    }
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
              if (mounted) setState(() => _pdfError = details.description);
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
              if (mounted) setState(() => _pdfError = details.description);
            },
            pageLayoutMode: PdfPageLayoutMode.continuous,
            scrollDirection: PdfScrollDirection.vertical,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            canShowPaginationDialog: true,
          );

    return Stack(
      children: [
        pdfWidget,

        // Loading indicator
        if (!_pdfLoaded && _pdfError == null)
          Container(
            color: context.bgColor,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Loading PDF...',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Error state
        if (_pdfError != null)
          Container(
            color: context.bgColor,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 64, color: AppColors.error),
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
                      _pdfError!,
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
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
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
    if (_videoError != null) {
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
                _videoError!,
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

    return Center(
      child: Chewie(controller: _chewieController!),
    );
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
              Icon(Icons.broken_image_outlined,
                  size: 64, color: context.textSecondary),
              const SizedBox(height: 12),
              Text('Failed to load image',
                  style: TextStyle(
                      fontFamily: 'Poppins', color: context.textSecondary)),
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
            Icon(Icons.insert_drive_file_outlined,
                size: 64, color: context.textSecondary),
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
