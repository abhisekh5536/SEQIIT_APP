import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/marketplace_models.dart';
import '../../../services/marketplace_service.dart';
import '../../../theme/app_theme.dart';
import '../widgets/marketplace_widgets.dart';

/// A photo on the form: either already uploaded ([url]) or picked locally.
class _Photo {
  final String? url;
  final Uint8List? bytes;
  final String ext;

  const _Photo.remote(String this.url)
      : bytes = null,
        ext = '';
  const _Photo.local(Uint8List this.bytes, this.ext) : url = null;
}

/// Create or edit a listing. Seller name, flat and phone are never asked
/// for — the server attaches them from the signed-in resident.
class PostListingScreen extends StatefulWidget {
  final MarketplaceContext marketplaceContext;
  final List<MarketplaceCategory> categories;
  final MarketplaceListing? existing;

  const PostListingScreen({
    super.key,
    required this.marketplaceContext,
    required this.categories,
    this.existing,
  });

  @override
  State<PostListingScreen> createState() => _PostListingScreenState();
}

class _PostListingScreenState extends State<PostListingScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;

  late List<_Photo> _photos;
  late PriceType _priceType;
  String? _categoryId;
  bool _submitting = false;
  String? _progress;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _descriptionController = TextEditingController(text: e?.description ?? '');
    _priceController = TextEditingController(
      text: e?.price == null ? '' : e!.price!.round().toString(),
    );
    _photos = [for (final i in e?.images ?? const []) _Photo.remote(i.imageUrl)];
    _priceType = e?.priceType ?? PriceType.fixed;
    final validIds = widget.categories.map((c) => c.id).toSet();
    _categoryId = validIds.contains(e?.categoryId) ? e?.categoryId : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  int get _slotsLeft => MarketplaceService.maxPhotos - _photos.length;

  Future<void> _addPhotos() async {
    if (_slotsLeft <= 0) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('Choose from gallery (up to $_slotsLeft)'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picker = ImagePicker();
      final List<XFile> picked;
      if (source == ImageSource.camera) {
        final one = await picker.pickImage(
          source: source,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 82,
        );
        picked = one == null ? const [] : [one];
      } else {
        picked = await picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 82,
          limit: _slotsLeft > 1 ? _slotsLeft : null,
        );
      }
      final added = <_Photo>[];
      for (final x in picked.take(_slotsLeft)) {
        final ext = x.name.contains('.')
            ? x.name.split('.').last.toLowerCase()
            : 'jpg';
        added.add(_Photo.local(await x.readAsBytes(), ext));
      }
      if (!mounted || added.isEmpty) return;
      setState(() {
        _photos = [..._photos, ...added];
        _error = null;
      });
    } catch (e) {
      debugPrint('PostListingScreen._addPhotos error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add photo: $e')),
        );
      }
    }
  }

  Future<void> _photoOptions(int index) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (index != 0)
              ListTile(
                leading: const Icon(Icons.star_outline_rounded),
                title: const Text('Make cover photo'),
                onTap: () => Navigator.pop(ctx, 'cover'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove photo'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    setState(() {
      final list = [..._photos];
      final photo = list.removeAt(index);
      if (action == 'cover') list.insert(0, photo);
      _photos = list;
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      setState(() => _error = 'Add at least one photo — listings with photos sell faster');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = 'Choose a category');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });
    HapticFeedback.mediumImpact();

    final service = MarketplaceService.instance;
    final uploadedNow = <String>[];
    try {
      final urls = <String>[];
      final localCount = _photos.where((ph) => ph.url == null).length;
      for (final ph in _photos) {
        if (ph.url != null) {
          urls.add(ph.url!);
          continue;
        }
        setState(() => _progress =
            'Uploading photo ${uploadedNow.length + 1} of $localCount…');
        final url = await service.uploadImage(
          bytes: ph.bytes!,
          fileExtension: ph.ext,
        );
        uploadedNow.add(url);
        urls.add(url);
      }
      setState(() => _progress = _isEdit ? 'Saving changes…' : 'Publishing…');

      final price = _priceType.needsAmount
          ? double.tryParse(_priceController.text.trim())
          : null;

      if (_isEdit) {
        await service.updateListing(
          listingId: widget.existing!.id,
          title: _titleController.text,
          description: _descriptionController.text,
          price: price,
          priceType: _priceType,
          categoryId: _categoryId!,
          imageUrls: urls,
        );
        final dropped = widget.existing!.images
            .map((i) => i.imageUrl)
            .where((u) => !urls.contains(u))
            .toList();
        await service.removeUploadedImages(dropped);
      } else {
        await service.createListing(
          title: _titleController.text,
          description: _descriptionController.text,
          price: price,
          priceType: _priceType,
          categoryId: _categoryId!,
          imageUrls: urls,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_isEdit
            ? 'Listing updated'
            : 'Your item is live for your neighbours'),
      ));
      Navigator.pop(context, true);
    } on MarketplaceException catch (e) {
      await service.removeUploadedImages(uploadedNow);
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
        _progress = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.paletteFor(Theme.of(context).brightness);
    final ctx = widget.marketplaceContext;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ModuleHeader(
              title: _isEdit ? 'Edit listing' : 'Sell an item',
              subtitle: _isEdit
                  ? 'Changes show up in the feed right away'
                  : 'Visible only to residents of your society',
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    SellerIdentityStrip(
                      name: ctx.sellerName,
                      flat: ctx.sellerFlatLabel,
                      caption: ctx.hasPhone
                          ? 'From your resident profile · buyers tap to see your number'
                          : 'No phone on your resident profile — buyers cannot call you',
                    ),
                    const SizedBox(height: 18),
                    FieldLabel('Photos (${_photos.length}/${MarketplaceService.maxPhotos})',
                        required: true),
                    _buildPhotoStrip(p),
                    const SizedBox(height: 4),
                    Text(
                      'First photo is the cover. Tap a photo to reorder or remove.',
                      style: textTheme.bodySmall?.copyWith(
                        color: p.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const FieldLabel('Title', required: true),
                    TextFormField(
                      controller: _titleController,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'e.g. Study table with drawer',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '').trim().length < 3
                          ? 'At least 3 characters'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('Category', required: true),
                    DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Choose a category',
                      ),
                      items: [
                        for (final c in widget.categories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Row(
                              children: [
                                Icon(categoryIcon(c.iconKey),
                                    size: 18, color: p.textSecondary),
                                const SizedBox(width: 10),
                                Text(c.name),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                    const SizedBox(height: 18),
                    const FieldLabel('Price', required: true),
                    SegmentedButton<PriceType>(
                      segments: [
                        for (final t in PriceType.values)
                          ButtonSegment(value: t, label: Text(t.label)),
                      ],
                      selected: {_priceType},
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(
                        textStyle: const TextStyle(fontSize: 12),
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (s) =>
                          setState(() => _priceType = s.first),
                    ),
                    if (_priceType.needsAmount) ...[
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(9),
                        ],
                        decoration: const InputDecoration(
                          prefixText: '₹ ',
                          hintText: '0',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (!_priceType.needsAmount) return null;
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null) return 'Enter a price';
                          if (n <= 0) return 'Use "Free" for giveaways';
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    const FieldLabel('Description'),
                    TextFormField(
                      controller: _descriptionController,
                      maxLength: 2000,
                      minLines: 4,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText:
                            'Condition, age, size, reason for selling, pickup timing…',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (!_isEdit) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Listings stay live for ${ctx.listingExpiryDays} days, then expire. You can relist anytime.',
                        style: textTheme.bodySmall?.copyWith(
                          color: p.textTertiary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_error != null) FormError(_error!),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: p.card,
                  border: Border(top: BorderSide(color: p.hairline)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _submitting
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(_progress ?? 'Working…'),
                            ],
                          )
                        : Text(_isEdit ? 'Save changes' : 'Post listing'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoStrip(AppPaletteData p) {
    const size = 92.0;
    return SizedBox(
      height: size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < _photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _submitting ? null : () => _photoOptions(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _photos[i].url != null
                            ? ListingImage(url: _photos[i].url)
                            : Image.memory(_photos[i].bytes!, fit: BoxFit.cover),
                        if (i == 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.5),
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: const Text(
                                'Cover',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_slotsLeft > 0)
            InkWell(
              onTap: _submitting ? null : _addPhotos,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: p.cardMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.hairline),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: p.primary),
                    const SizedBox(height: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        color: p.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
