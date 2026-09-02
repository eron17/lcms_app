import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class FileDownloader {
  static Future<void> downloadAndOpen({
    required BuildContext context,
    required String url,
    required String fileName,
  }) async {
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadProgressDialog(
        url: url,
        fileName: fileName,
      ),
    );
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final String url;
  final String fileName;

  const _DownloadProgressDialog({
    required this.url,
    required this.fileName,
  });

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String _status = 'Downloading...';
  bool _done = false;
  bool _error = false;
  String _errorMessage = 'Download failed. Please try again.';
  final Dio _dio = Dio();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _dio.close(force: true);
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/${widget.fileName}';

      await _dio.download(
        widget.url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            setState(() {
              _progress = received / total;
              _status = '${(_progress * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _done = true;
          _status = 'Opening file...';
        });
      }

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.of(context).pop();
      }

      final result = await OpenFilex.open(filePath);

      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open file: ${result.message}',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: const Color(0xFF111d33),
          ),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _errorMessage = e.type == DioExceptionType.connectionError
              ? 'No internet connection.\n'
                    'Please check your network and try again.'
              : 'Download failed.\nPlease try again.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = true;
          _errorMessage = 'Download failed.\nPlease try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _done || _error,
      child: AlertDialog(
        backgroundColor: const Color(0xFF111d33),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          _error
              ? 'Download Failed'
              : _done
              ? 'Opening File'
              : 'Downloading File',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.fileName,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            if (!_error) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: _done
                      ? 1.0
                      : _progress > 0
                      ? _progress
                      : null,
                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(
                    _done ? const Color(0xFF4CAF50) : const Color(0xFF3B9EFF),
                  ),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _status,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _done
                      ? const Color(0xFF4CAF50)
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ] else ...[
              Text(
                _errorMessage,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: Color(0xFFFF5252),
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (_error)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Close',
                style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF3B9EFF)),
              ),
            ),
        ],
      ),
    );
  }
}
