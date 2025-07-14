import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:google_fonts/google_fonts.dart';

// Confirmation buttons (Yes/No)
Widget buildConfirmationButtons(
    AnimationController scaleController, Function(String) handleConfirmation) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      // Yes button
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedBuilder(
          animation: scaleController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (scaleController.value * 0.1),
              child: child,
            );
          },
          child: ElevatedButton.icon(
            icon: Icon(Icons.check_circle, size: 32),
            label: Text(
              'Yes!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => handleConfirmation('yes'),
          ),
        ),
      ),

      // No button
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: AnimatedBuilder(
          animation: scaleController,
          builder: (context, child) {
            return Transform.scale(
              scale: 1.0 + (scaleController.value * 0.1),
              child: child,
            );
          },
          child: ElevatedButton.icon(
            icon: Icon(Icons.cancel, size: 32),
            label: Text(
              'No!',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () => handleConfirmation('no'),
          ),
        ),
      ),
    ],
  );
}

// Continuation buttons for ongoing stories
Widget buildContinuationButtons(List<Map<String, dynamic>> continuationOptions,
    AnimationController bounceController, Function(String) requestStory) {
  return ListView.builder(
    scrollDirection: Axis.horizontal,
    padding: EdgeInsets.symmetric(horizontal: 12),
    itemCount: continuationOptions.length,
    itemBuilder: (context, index) {
      final option = continuationOptions[index];
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: AnimatedBuilder(
          animation: bounceController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(
                  0,
                  math.sin((bounceController.value + index * 0.2) * math.pi) *
                      5),
              child: child,
            );
          },
          child: InkWell(
            onTap: () => requestStory(option['name']),
            child: Container(
              width: 120,
              decoration: BoxDecoration(
                color: option['color'],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 5,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                      child: Icon(
                    option['icon'],
                    size: 30,
                    color: Colors.white,
                  )),
                  const SizedBox(height: 4),
                  Expanded(
                      child: Text(
                    option['name'],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontFamily: GoogleFonts.montserrat().fontFamily,
                    ),
                    textAlign: TextAlign.center,
                  )),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// Theme buttons for story generation
Widget buildThemeButtons(
  List<Map<String, dynamic>> storyThemes,
  Function(String) generateThemedStory,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: storyThemes.map((theme) {
        return InkWell(
          onTap: () => generateThemedStory(theme['theme']),
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: theme['color'],
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 5,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(theme['icon'], size: 50, color: Colors.white),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Text(
                    theme['name'],
                    style: TextStyle(
                      fontSize: 14,
                      fontFamily: GoogleFonts.montserrat(
                        fontWeight: FontWeight.bold,
                      ).fontFamily,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}
