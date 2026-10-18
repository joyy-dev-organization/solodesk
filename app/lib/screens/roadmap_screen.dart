import 'package:flutter/material.dart';
import '../widgets/unfinished_placeholder.dart';




class RepeatWorkScreen extends StatelessWidget {
  const RepeatWorkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: UnfinishedPlaceholder(
        title: 'Repeat Work',
        milestone: 'Milestone M7 · P2 Priority',
        description: 'Service plan retainers and recurring renewal proposals.',
        plannedDetails: 'Repeat Work will package recurring freelance deliverables into monthly retainers, '
            'track renewal dates, and draft recurring service offers based on proven client relationships.',
        icon: Icons.autorenew_outlined,
      ),
    );
  }
}
