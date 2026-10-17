import 'package:flutter/material.dart';
import '../widgets/unfinished_placeholder.dart';

class PolitePayScreen extends StatelessWidget {
  const PolitePayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: UnfinishedPlaceholder(
        title: 'PolitePay',
        milestone: 'Milestone M5 · P1 Priority',
        description: 'Invoice tracking with exact minor-unit arithmetic in Dart and polite, AI-drafted payment reminders.',
        plannedDetails: 'PolitePay will calculate overdue dates, compute outstanding balances from SQLite invoice records, '
            'and draft polite payment reminder messages adapted to tone (Friendly, Firm, Final) '
            'without sending real emails or inventing dates.',
        icon: Icons.attach_money_outlined,
      ),
    );
  }
}

class LeadLoopScreen extends StatelessWidget {
  const LeadLoopScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: UnfinishedPlaceholder(
        title: 'LeadLoop',
        milestone: 'Milestone M6 · P2 Priority',
        description: 'Prospect pipeline management and follow-up scheduling across freelancer service niches.',
        plannedDetails: 'LeadLoop will track prospective client enquiries, manage pipeline stages (New Lead, Proposal Sent, Follow-up), '
            'and schedule timely follow-up reminders directly on your Windows desktop.',
        icon: Icons.people_outline,
      ),
    );
  }
}

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
