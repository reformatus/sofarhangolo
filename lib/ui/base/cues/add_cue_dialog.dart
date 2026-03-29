import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../services/app_links/navigation.dart';
import '../../../services/cue/write_cue.dart';
import '../../cue/cue_page_type.dart';

class EditCueDialog extends StatefulWidget {
  const EditCueDialog({super.key});

  @override
  EditCueDialogState createState() => EditCueDialogState();
}

class EditCueDialogState extends State<EditCueDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  bool isSaving = false;

  @override
  Widget build(BuildContext context) {
    onSubmit() {
      if (_formKey.currentState!.validate()) {
        setState(() => isSaving = true);
        insertNewCue(
          title: _titleController.text,
          description: _descriptionController.text,
        ).then((cue) {
          // ignore: use_build_context_synchronously
          context.pop();
          // ignore: use_build_context_synchronously
          context.push(cueRoutePath(cue.uuid, CuePageType.edit));
        });
      }
    }

    return AlertDialog(
      title: Text('Lista létrehozása'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                decoration: InputDecoration(hintText: 'Cím'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Kötelező címet adni a listának!';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => onSubmit(),
              ),
              TextFormField(
                controller: _descriptionController,
                maxLines: null,
                decoration: InputDecoration(hintText: 'Leírás'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: isSaving ? null : () => context.pop(),
          child: Text('Mégse'),
        ),
        FilledButton(
          onPressed: onSubmit,
          child: AnimatedSize(
            duration: Durations.medium1,
            child: isSaving
                ? SizedBox(width: 50, child: LinearProgressIndicator())
                : Text('Létrehozás'),
          ),
        ),
      ],
    );
  }
}
