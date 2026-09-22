import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sqot/models/training_session.dart';
import 'package:sqot/services/settings_service.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final SettingsService _settingsService = SettingsService.instance;

  bool _isLoading = true;
  List<TrainingSession> _sessions = <TrainingSession>[];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    if (!_settingsService.isInitialized) {
      await _settingsService.loadSettings();
    }

    final sessions = _settingsService.getSavedTrainingSessions();
    if (!mounted) {
      return;
    }

    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-$month-$day $hour:$minute';
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  Future<void> _renameSession(TrainingSession session) async {
    final controller = TextEditingController(text: session.title ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit session title'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Optional title',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (result == null) {
      return;
    }

    final updatedSession = TrainingSession(
      id: session.id,
      title: result.isEmpty ? null : result,
      trainingTypeTitle: session.trainingTypeTitle,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      dataPoints: session.dataPoints,
    );

    await _settingsService.updateTrainingSession(updatedSession);
    await _loadSessions();
  }

  Future<void> _deleteSession(TrainingSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete session'),
          content: Text(
            'Delete "${session.title ?? session.trainingTypeTitle}"?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _settingsService.deleteTrainingSession(session.id);
    await _loadSessions();

    if (!mounted) {
      return;
    }

    Get.snackbar('Session deleted', 'The recorded session was removed.');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessions.isEmpty) {
      return const Center(child: Text('No recorded sessions yet.'));
    }

    final colorScheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final session = _sessions[index];
          final duration = session.endedAt.difference(session.startedAt);

          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: colorScheme.surfaceContainerLow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title ?? session.trainingTypeTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameSession(session);
                          break;
                        case 'delete':
                          _deleteSession(session);
                          break;
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text('Training type: ${session.trainingTypeTitle}'),
                Text('Started: ${_formatTimestamp(session.startedAt)}'),
                Text('Ended: ${_formatTimestamp(session.endedAt)}'),
                Text('Duration: ${_formatDuration(duration)}'),
                Text('Datapoints: ${session.dataPoints.length}'),
              ],
            ),
          );
        },
      ),
    );
  }
}
