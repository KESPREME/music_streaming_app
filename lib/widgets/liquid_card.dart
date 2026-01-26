import 'package:flutter/material.dart';

class LiquidCard extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final double width;
  final double height;
  final bool isCircle; // For artists or specific circles

  const LiquidCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.width = 160,
    this.height = 160,
    this.isCircle = false,
  });

  @override
  State<LiquidCard> createState() => _LiquidCardState();
}

class _LiquidCardState extends State<LiquidCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
       vsync: this,
       duration: const Duration(milliseconds: 150),
       lowerBound: 0.0,
       upperBound: 0.1,
    );
     _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
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
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
         _controller.reverse();
         widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              margin: const EdgeInsets.only(right: 16), // Spacing between cards
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   // Image Container
                   Container(
                     height: widget.height,
                     width: widget.width,
                     decoration: BoxDecoration(
                       borderRadius: BorderRadius.circular(widget.isCircle ? widget.width / 2 : 24),
                       boxShadow: [
                         BoxShadow(
                           color: Colors.black.withOpacity(0.2),
                           blurRadius: 10,
                           offset: const Offset(0, 5),
                         ),
                       ],
                     ),
                     child: ClipRRect(
                       borderRadius: BorderRadius.circular(widget.isCircle ? widget.width / 2 : 24),
                       child: Stack(
                         children: [
                            // 1. Background Image
                            Positioned.fill(
                               child: widget.imageUrl.startsWith('http') 
                                  ? Image.network(
                                       widget.imageUrl,
                                       fit: BoxFit.cover,
                                       errorBuilder: (_,__,___) => Container(color: Colors.grey[800]),
                                    )
                                  : Container(color: Colors.grey[800]), // Fallback
                            ),
                            
                            // 2. Gradient Overlay (Bottom)
                            if (!widget.isCircle)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: widget.height * 0.5,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.8),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            
                            // 3. Play Icon (Optional, appears on hover ideally, but here maybe just static or tapped)
                         ],
                       ),
                     ),
                   ),
                   const SizedBox(height: 12),
                   
                   // Title
                   Text(
                     widget.title,
                     style: const TextStyle(
                       fontWeight: FontWeight.bold,
                       fontSize: 14,
                       color: Colors.white,
                       letterSpacing: 0.5,
                     ),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                   
                   // Subtitle
                   if (widget.subtitle.isNotEmpty)
                   Text(
                     widget.subtitle,
                     style: TextStyle(
                       fontWeight: FontWeight.w500,
                       fontSize: 12,
                       color: Colors.white.withOpacity(0.6),
                     ),
                     maxLines: 1,
                     overflow: TextOverflow.ellipsis,
                   ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
