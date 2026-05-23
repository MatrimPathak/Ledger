import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/category.dart';
import '../../../providers/firestore_provider.dart';

class AddCategoryBottomSheet extends ConsumerStatefulWidget {
  final String userId;

  const AddCategoryBottomSheet({super.key, required this.userId});

  @override
  ConsumerState<AddCategoryBottomSheet> createState() =>
      _AddCategoryBottomSheetState();
}

class _AddCategoryBottomSheetState
    extends ConsumerState<AddCategoryBottomSheet> {
  final _titleCtrl = TextEditingController();
  int _selectedIconIndex = 0;
  int _selectedColorIndex = 0;
  bool _saving = false;

  static const _icons = [
    Icons.restaurant,
    Icons.directions_car,
    Icons.movie_outlined,
    Icons.shopping_bag_outlined,
    Icons.receipt_outlined,
    Icons.local_hospital_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.trending_up,
    Icons.local_grocery_store_outlined,
    Icons.school_outlined,
    Icons.flight,
    Icons.home_outlined,
    Icons.fitness_center,
    Icons.music_note_outlined,
    Icons.sports_soccer,
    Icons.pets,
    Icons.phone_outlined,
    Icons.wifi,
    Icons.car_repair,
    Icons.water_drop_outlined,
    Icons.electric_bolt_outlined,
    Icons.local_cafe_outlined,
    Icons.subscriptions_outlined,
    Icons.attach_money,
    Icons.swap_horiz,
    Icons.child_care,
    Icons.celebration_outlined,
    Icons.volunteer_activism_outlined,
    Icons.travel_explore_outlined,
    Icons.more_horiz,
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category name')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      final now = DateTime.now();
      final category = Category(
        id: '',
        userId: widget.userId,
        title: _titleCtrl.text.trim(),
        iconCodePoint: _icons[_selectedIconIndex].codePoint,
        colorValue: AppColors.categoryColors[_selectedColorIndex].value,
        createdAt: now,
      );
      final created = await firestoreService.createCategory(category);
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to create: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = AppColors.categoryColors[_selectedColorIndex];
    final selectedIcon = _icons[_selectedIconIndex];
    final title = _titleCtrl.text.isEmpty ? 'Category' : _titleCtrl.text;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const SizedBox(height: 8),
          // Live preview
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: selectedColor.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(selectedIcon, color: selectedColor, size: 32),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: selectedColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Category Name', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _titleCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'e.g. Coffee, Gym, Netflix...'),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          Text('Color', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: AppColors.categoryColors.asMap().entries.map((entry) {
              final selected = _selectedColorIndex == entry.key;
              return GestureDetector(
                onTap: () => setState(() => _selectedColorIndex = entry.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: theme.colorScheme.onSurface, width: 3)
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Icon', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 6,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _icons.length,
            itemBuilder: (ctx, i) {
              final selected = _selectedIconIndex == i;
              return GestureDetector(
                onTap: () => setState(() => _selectedIconIndex = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: selected
                        ? selectedColor.withOpacity(0.2)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: selected
                        ? Border.all(color: selectedColor, width: 2)
                        : Border.all(color: theme.colorScheme.outline),
                  ),
                  child: Icon(
                    _icons[i],
                    color: selected
                        ? selectedColor
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                    size: 22,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Add Category'),
            ),
          ),
        ],
      ),
    );
  }
}
