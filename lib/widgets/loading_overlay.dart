import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../api/tmdb_api.dart';
import '../utils/app_theme.dart';

class LoadingOverlay extends StatefulWidget {
  final Movie movie;
  final String? message;
  const LoadingOverlay({super.key, required this.movie, this.message});

  @override
  State<LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<LoadingOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred Backdrop
          CachedNetworkImage(
            imageUrl: TmdbApi.getImageUrl(widget.movie.backdropPath),
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.black),
            errorWidget: (context, url, error) => Container(color: Colors.black),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
          
          // Logo/Title (Restored clear logo logic)
          Center(
            child: FadeTransition(
              opacity: _animation,
              child: widget.movie.logoPath.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: TmdbApi.getImageUrl(widget.movie.logoPath),
                      width: MediaQuery.of(context).size.width * 0.6,
                      fit: BoxFit.contain,
                    )
                  : Text(
                      widget.movie.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        fontFamily: 'Poppins',
                      ),
                    ),
            ),
          ),
          
          // Status
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                const CircularProgressIndicator(color: AppTheme.primaryColor, strokeWidth: 3),
                const SizedBox(height: 32),
                Text(
                  widget.message?.toUpperCase() ?? 'STARTING STREAM',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
