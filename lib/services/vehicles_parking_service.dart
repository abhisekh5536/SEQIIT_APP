import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/vehicle_parking_models.dart';

/// Central service for Vehicle Registry, Parking Slot Inventory,
/// Flat Allocations, and Guard Gate Logging.
class VehiclesParkingService extends ChangeNotifier {
  VehiclesParkingService._();
  static final VehiclesParkingService instance = VehiclesParkingService._();

  SupabaseClient? get _safeClient {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _client =>
      _safeClient ?? SupabaseClient('http://localhost', 'anon');

  // In-memory caches for fast reactive UI updates
  List<ParkingSlotItem> _slots = [];
  List<VehicleItem> _societyVehicles = [];
  List<ParkingAllocationItem> _allocations = [];
  List<VehicleEntryLogItem> _recentLogs = [];
  ParkingPolicyConfig? _policyConfig;

  List<ParkingBayRequestItem> _bayRequests = [];

  List<ParkingSlotItem> get slots => List.unmodifiable(_slots);
  List<VehicleItem> get societyVehicles => List.unmodifiable(_societyVehicles);
  List<ParkingAllocationItem> get allocations => List.unmodifiable(_allocations);
  List<VehicleEntryLogItem> get recentLogs => List.unmodifiable(_recentLogs);
  List<ParkingBayRequestItem> get bayRequests => List.unmodifiable(_bayRequests);
  ParkingPolicyConfig? get policyConfig => _policyConfig;

  /// Last load error per data set, so screens can show a real failure
  /// instead of silently rendering stale or sample rows.
  final Map<String, String> _loadErrors = {};

  String? errorFor(String key) => _loadErrors[key];
  bool get hasAnyError => _loadErrors.isNotEmpty;

  void _setError(String key, Object e) {
    _loadErrors[key] = _humanize(e);
    debugPrint('VehiclesParkingService[$key] error: $e');
  }

  void _clearError(String key) => _loadErrors.remove(key);

  String _humanize(Object e) {
    if (e is PostgrestException) {
      if (e.code == '42501' || e.message.toLowerCase().contains('row-level security')) {
        return 'You do not have access to this society\'s parking records.';
      }
      if (e.code == '22P02') {
        return 'This account is not linked to a society yet.';
      }
      return e.message;
    }
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException')) {
      return 'No connection to the server. Check the network and retry.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  /// Sample rows are only ever used when Supabase itself is not wired up
  /// (widget tests, previews). They must never stand in for a failed query —
  /// a guard reading invented entries out of the gate register is worse
  /// than a guard seeing an error.
  bool get _isOffline => _safeClient == null;

  // ─────────────────────────────────────────────────────────────
  // 1. SLOTS INVENTORY (Society Admin)
  // ─────────────────────────────────────────────────────────────

  Future<List<ParkingSlotItem>> fetchSlots({
    required String societyId,
    String? blockId,
    SlotStatus? statusFilter,
    VehicleType? typeFilter,
  }) async {
    if (_isOffline) {
      _slots = _mockSlots();
      notifyListeners();
      return _slots;
    }
    if (societyId.isEmpty) {
      _slots = [];
      _setError('slots', 'This account is not linked to a society yet.');
      notifyListeners();
      return _slots;
    }

    try {
      var query = _client
          .from('parking_slots')
          .select('''
            *,
            blocks(name),
            parking_allocations(
              id, flat_id, status, allocated_from, vehicle_id,
              flats(flat_number, blocks(name)),
              residents(full_name),
              vehicles(vehicle_number, make_model)
            )
          ''')
          .eq('society_id', societyId);

      if (blockId != null && blockId.isNotEmpty) {
        query = query.eq('block_id', blockId);
      }
      if (statusFilter != null) {
        query = query.eq('status', statusFilter.toDbValue());
      }
      if (typeFilter != null) {
        query = query.eq('vehicle_type', typeFilter.toDbValue());
      }

      final res = await query.order('slot_number', ascending: true);
      final list = (res as List).cast<Map<String, dynamic>>();
      _slots = list.map(ParkingSlotItem.fromMap).toList();
      _clearError('slots');
      notifyListeners();
      return _slots;
    } catch (e) {
      _slots = [];
      _setError('slots', e);
      notifyListeners();
      return _slots;
    }
  }

  Future<ParkingSlotItem?> createSlot({
    required String societyId,
    required String slotNumber,
    String? blockId,
    required VehicleType vehicleType,
    required SlotCategory category,
  }) async {
    final cleanSlot = slotNumber.trim().toUpperCase();
    if (_safeClient == null) {
      final newSlot = ParkingSlotItem(
        id: 'slot-${DateTime.now().millisecondsSinceEpoch}',
        societyId: societyId,
        blockId: blockId,
        slotNumber: cleanSlot,
        vehicleType: vehicleType,
        category: category,
        status: SlotStatus.vacant,
        createdAt: DateTime.now(),
      );
      _slots.insert(0, newSlot);
      notifyListeners();
      return newSlot;
    }

    try {
      final res = await _client.from('parking_slots').insert({
        'society_id': societyId,
        'slot_number': cleanSlot,
        if (blockId != null && blockId.isNotEmpty) 'block_id': blockId,
        'vehicle_type': vehicleType.toDbValue(),
        'category': category.toDbValue(),
        'status': 'vacant',
      }).select().single();

      final created = ParkingSlotItem.fromMap(res);
      await fetchSlots(societyId: societyId);
      return created;
    } catch (e) {
      debugPrint('VehiclesParkingService.createSlot error: $e');
      rethrow;
    }
  }

  Future<int> bulkCreateSlots({
    required String societyId,
    required String prefix,
    required int startNum,
    required int endNum,
    String? blockId,
    required VehicleType vehicleType,
    required SlotCategory category,
  }) async {
    if (_safeClient == null) {
      int count = 0;
      for (int i = startNum; i <= endNum; i++) {
        final slotNum = '$prefix${i.toString().padLeft(2, '0')}';
        _slots.add(ParkingSlotItem(
          id: 'slot-$i-${DateTime.now().millisecondsSinceEpoch}',
          societyId: societyId,
          blockId: blockId,
          slotNumber: slotNum,
          vehicleType: vehicleType,
          category: category,
          status: SlotStatus.vacant,
        ));
        count++;
      }
      notifyListeners();
      return count;
    }

    try {
      // Try calling RPC function first
      try {
        final rpcRes = await _client.rpc('bulk_create_parking_slots', params: {
          'p_society_id': societyId,
          'p_prefix': prefix,
          'p_start_num': startNum,
          'p_end_num': endNum,
          'p_block_id': blockId,
          'p_vehicle_type': vehicleType.toDbValue(),
          'p_category': category.toDbValue(),
        });
        if (rpcRes is Map && rpcRes['success'] == true) {
          await fetchSlots(societyId: societyId);
          return (rpcRes['created_count'] as int?) ?? (endNum - startNum + 1);
        }
      } catch (rpcErr) {
        debugPrint('bulk_create_parking_slots RPC failed, falling back to batch insert: $rpcErr');
      }

      // Batch insert fallback
      final List<Map<String, dynamic>> rows = [];
      for (int i = startNum; i <= endNum; i++) {
        final slotNum = '$prefix${i.toString().padLeft(2, '0')}';
        rows.add({
          'society_id': societyId,
          'slot_number': slotNum,
          if (blockId != null && blockId.isNotEmpty) 'block_id': blockId,
          'vehicle_type': vehicleType.toDbValue(),
          'category': category.toDbValue(),
          'status': 'vacant',
        });
      }

      await _client.from('parking_slots').upsert(rows, onConflict: 'society_id,slot_number');
      await fetchSlots(societyId: societyId);
      return rows.length;
    } catch (e) {
      debugPrint('VehiclesParkingService.bulkCreateSlots error: $e');
      rethrow;
    }
  }

  Future<void> updateSlotStatus({
    required String slotId,
    required SlotStatus status,
    required String societyId,
  }) async {
    if (_safeClient == null) {
      final idx = _slots.indexWhere((s) => s.id == slotId);
      if (idx != -1) {
        _slots[idx] = _slots[idx].copyWith(status: status);
        notifyListeners();
      }
      return;
    }

    try {
      await _client
          .from('parking_slots')
          .update({'status': status.toDbValue()})
          .eq('id', slotId);
      await fetchSlots(societyId: societyId);
    } catch (e) {
      debugPrint('VehiclesParkingService.updateSlotStatus error: $e');
      rethrow;
    }
  }

  Future<void> deleteSlot({
    required String slotId,
    required String societyId,
  }) async {
    if (_safeClient == null) {
      _slots.removeWhere((s) => s.id == slotId);
      notifyListeners();
      return;
    }

    try {
      await _client.from('parking_slots').delete().eq('id', slotId);
      await fetchSlots(societyId: societyId);
    } catch (e) {
      debugPrint('VehiclesParkingService.deleteSlot error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 2. ALLOCATION MANAGEMENT (Society Admin)
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> allocateSlot({
    required String societyId,
    required String slotId,
    required String flatId,
    String? residentId,
    String? vehicleId,
    String? notes,
  }) async {
    if (_safeClient == null) {
      final slotIdx = _slots.indexWhere((s) => s.id == slotId);
      if (slotIdx != -1) {
        _slots[slotIdx] = _slots[slotIdx].copyWith(
          status: SlotStatus.allocated,
          activeAllocation: ActiveSlotAllocation(
            allocationId: 'alloc-${DateTime.now().millisecondsSinceEpoch}',
            flatId: flatId,
            flatNumber: 'Sample Flat',
            blockName: 'Tower A',
            vehicleId: vehicleId,
            allocatedFrom: DateTime.now(),
          ),
        );
        notifyListeners();
      }
      return {'success': true};
    }

    try {
      // 1. Attempt RPC call for atomic validation and allocation
      try {
        final rpcRes = await _client.rpc('allocate_parking_slot', params: {
          'p_society_id': societyId,
          'p_slot_id': slotId,
          'p_flat_id': flatId,
          'p_resident_id': residentId,
          'p_vehicle_id': vehicleId,
          'p_notes': notes,
        });

        if (rpcRes is Map) {
          final map = Map<String, dynamic>.from(rpcRes);
          if (map['success'] == true) {
            await fetchSlots(societyId: societyId);
            await fetchSocietyVehicles(societyId: societyId);
            return map;
          } else {
            throw Exception(map['error'] ?? 'Slot allocation failed');
          }
        }
      } on PostgrestException catch (rpcErr) {
        // Only fallback to direct insert if the RPC function itself does not exist (code 42883)
        if (rpcErr.code == '42883') {
          debugPrint('allocate_parking_slot RPC missing, trying direct insert fallback: $rpcErr');
        } else {
          rethrow;
        }
      } catch (e) {
        // Rethrow business validation exceptions or permission errors
        rethrow;
      }

      // 2. Direct insert fallback (only reached if RPC function is not in database)
      final res = await _client.from('parking_allocations').insert({
        'society_id': societyId,
        'slot_id': slotId,
        'flat_id': flatId,
        'resident_id': ?residentId,
        'vehicle_id': ?vehicleId,
        'allocated_from': DateTime.now().toIso8601String(),
        'status': 'active',
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }).select().single();

      // Trigger handles slot status, but let's ensure it's marked
      await _client
          .from('parking_slots')
          .update({'status': 'allocated'})
          .eq('id', slotId);

      await fetchSlots(societyId: societyId);
      await fetchSocietyVehicles(societyId: societyId);
      return {'success': true, 'data': res};
    } catch (e) {
      debugPrint('VehiclesParkingService.allocateSlot error: $e');
      rethrow;
    }
  }

  Future<void> endAllocation({
    required String allocationId,
    required String societyId,
    String? notes,
  }) async {
    if (_safeClient == null) {
      for (int i = 0; i < _slots.length; i++) {
        if (_slots[i].activeAllocation?.allocationId == allocationId) {
          _slots[i] = _slots[i].copyWith(
            status: SlotStatus.vacant,
            activeAllocation: null,
          );
        }
      }
      notifyListeners();
      return;
    }

    try {
      // 1. Try RPC
      try {
        final rpcRes = await _client.rpc('end_parking_allocation', params: {
          'p_allocation_id': allocationId,
          'p_notes': notes,
        });
        if (rpcRes is Map && rpcRes['success'] == true) {
          await fetchSlots(societyId: societyId);
          await fetchSocietyVehicles(societyId: societyId);
          return;
        }
      } catch (rpcErr) {
        debugPrint('end_parking_allocation RPC fallback: $rpcErr');
      }

      // 2. Direct update fallback
      final allocRes = await _client
          .from('parking_allocations')
          .update({
            'status': 'ended',
            'allocated_until': DateTime.now().toIso8601String(),
            'notes': ?notes,
          })
          .eq('id', allocationId)
          .select('slot_id')
          .single();

      final slotId = allocRes['slot_id'];
      if (slotId != null) {
        await _client
            .from('parking_slots')
            .update({'status': 'vacant'})
            .eq('id', slotId);
      }

      await fetchSlots(societyId: societyId);
      await fetchSocietyVehicles(societyId: societyId);
    } catch (e) {
      debugPrint('VehiclesParkingService.endAllocation error: $e');
      rethrow;
    }
  }

  Future<List<ParkingAllocationItem>> fetchAllocations({
    required String societyId,
    String? flatId,
    AllocationStatus? status,
  }) async {
    if (_isOffline) {
      _allocations = _mockAllocations();
      notifyListeners();
      return _allocations;
    }
    if (societyId.isEmpty) {
      _allocations = [];
      _setError('allocations', 'This account is not linked to a society yet.');
      notifyListeners();
      return _allocations;
    }

    try {
      var query = _client
          .from('parking_allocations')
          .select('''
            *,
            parking_slots(slot_number, category, vehicle_type),
            flats(flat_number, blocks(name)),
            residents(full_name),
            vehicles(vehicle_number, make_model)
          ''')
          .eq('society_id', societyId);

      if (flatId != null && flatId.isNotEmpty) {
        query = query.eq('flat_id', flatId);
      }
      if (status != null) {
        query = query.eq('status', status.toDbValue());
      }

      final res = await query.order('allocated_from', ascending: false);
      final list = (res as List).cast<Map<String, dynamic>>();
      _allocations = list.map(ParkingAllocationItem.fromMap).toList();
      _clearError('allocations');
      notifyListeners();
      return _allocations;
    } catch (e) {
      _allocations = [];
      _setError('allocations', e);
      notifyListeners();
      return _allocations;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 3. VEHICLE REGISTRY (Resident & Society Admin)
  // ─────────────────────────────────────────────────────────────

  Future<List<VehicleItem>> fetchSocietyVehicles({
    required String societyId,
    String? searchQuery,
    bool? unallocatedOnly,
  }) async {
    if (_isOffline) {
      _societyVehicles = _mockVehicles();
      notifyListeners();
      return _societyVehicles;
    }
    if (societyId.isEmpty) {
      _societyVehicles = [];
      _setError('vehicles', 'This account is not linked to a society yet.');
      notifyListeners();
      return _societyVehicles;
    }

    try {
      var query = _client
          .from('vehicles')
          .select('''
            *,
            flats(flat_number, blocks(name)),
            residents(full_name, phone, resident_type),
            parking_allocations(
              id, status,
              parking_slots(slot_number, category)
            )
          ''')
          .eq('society_id', societyId)
          .eq('status', 'active');

      final res = await query.order('created_at', ascending: false);
      final list = (res as List).cast<Map<String, dynamic>>();
      var items = list.map(VehicleItem.fromMap).toList();

      if (searchQuery != null && searchQuery.trim().isNotEmpty) {
        final q = searchQuery.trim().toLowerCase();
        items = items.where((v) {
          final plateMatch = v.vehicleNumber.toLowerCase().contains(q);
          final makeMatch = v.makeModel.toLowerCase().contains(q);
          final flatMatch = v.flatNumber.toLowerCase().contains(q);
          final resMatch = v.residentName.toLowerCase().contains(q);
          final slotMatch = v.allocatedSlotNumber?.toLowerCase().contains(q) ?? false;
          return plateMatch || makeMatch || flatMatch || resMatch || slotMatch;
        }).toList();
      }

      if (unallocatedOnly == true) {
        items = items.where((v) => !v.hasAllocatedSlot).toList();
      }

      _societyVehicles = items;
      _clearError('vehicles');
      notifyListeners();
      return _societyVehicles;
    } catch (e) {
      _societyVehicles = [];
      _setError('vehicles', e);
      notifyListeners();
      return _societyVehicles;
    }
  }

  Future<List<VehicleItem>> fetchMyFlatVehicles(String flatId) async {
    if (_isOffline) {
      return _mockVehicles().where((v) => v.flatId == flatId).toList();
    }
    if (flatId.isEmpty) {
      _setError('myVehicles', 'No flat is linked to this account yet.');
      return [];
    }

    try {
      final res = await _client
          .from('vehicles')
          .select('''
            *,
            flats(flat_number, blocks(name)),
            residents(full_name, phone, resident_type),
            parking_allocations(
              id, status,
              parking_slots(slot_number, category)
            )
          ''')
          .eq('flat_id', flatId)
          .order('created_at', ascending: false);

      final list = (res as List).cast<Map<String, dynamic>>();
      _clearError('myVehicles');
      return list.map(VehicleItem.fromMap).toList();
    } catch (e) {
      _setError('myVehicles', e);
      return [];
    }
  }

  Future<String?> uploadRcPhoto({
    required Uint8List bytes,
    required String fileExtension,
  }) async {
    if (_safeClient == null) return null;
    try {
      final user = _client.auth.currentUser;
      final userId = user?.id ?? 'anon';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = '$userId/$fileName';

      await _client.storage.from('vehicle-rc-docs').uploadBinary(
        filePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$fileExtension',
          upsert: true,
        ),
      );

      final publicUrl = _client.storage.from('vehicle-rc-docs').getPublicUrl(filePath);
      return publicUrl;
    } catch (e) {
      debugPrint('VehiclesParkingService.uploadRcPhoto error: $e');
      return null;
    }
  }

  Future<VehicleItem> registerVehicle({
    required String societyId,
    required String flatId,
    String? residentId,
    required String vehicleNumber,
    required String makeModel,
    required VehicleType type,
    String? color,
    String? rcPhotoUrl,
  }) async {
    final cleanPlate = vehicleNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (_safeClient == null) {
      final newVeh = VehicleItem(
        id: 'veh-${DateTime.now().millisecondsSinceEpoch}',
        societyId: societyId,
        flatId: flatId,
        residentId: residentId,
        type: type,
        vehicleNumber: cleanPlate,
        makeModel: makeModel,
        color: color,
        rcPhotoUrl: rcPhotoUrl,
        status: 'active',
        createdAt: DateTime.now(),
      );
      _societyVehicles.insert(0, newVeh);
      notifyListeners();
      return newVeh;
    }

    try {
      final res = await _client.from('vehicles').insert({
        'society_id': societyId,
        'flat_id': flatId,
        'resident_id': ?residentId,
        'vehicle_number': cleanPlate,
        'make_model': makeModel.trim(),
        'type': type.toDbValue(),
        if (color != null && color.trim().isNotEmpty) 'color': color.trim(),
        'rc_photo_url': ?rcPhotoUrl,
        'status': 'active',
      }).select().single();

      final created = VehicleItem.fromMap(res);
      await fetchSocietyVehicles(societyId: societyId);
      return created;
    } catch (e) {
      debugPrint('VehiclesParkingService.registerVehicle error: $e');
      rethrow;
    }
  }

  Future<void> updateVehicle({
    required String vehicleId,
    required String societyId,
    String? makeModel,
    String? color,
    VehicleType? type,
    String? rcPhotoUrl,
  }) async {
    if (_safeClient == null) {
      final idx = _societyVehicles.indexWhere((v) => v.id == vehicleId);
      if (idx != -1) {
        _societyVehicles[idx] = _societyVehicles[idx].copyWith(
          makeModel: makeModel,
          color: color,
          type: type,
          rcPhotoUrl: rcPhotoUrl,
        );
        notifyListeners();
      }
      return;
    }

    try {
      final updates = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (makeModel != null) updates['make_model'] = makeModel.trim();
      if (color != null) updates['color'] = color.trim();
      if (type != null) updates['type'] = type.toDbValue();
      if (rcPhotoUrl != null) updates['rc_photo_url'] = rcPhotoUrl;

      await _client.from('vehicles').update(updates).eq('id', vehicleId);
      await fetchSocietyVehicles(societyId: societyId);
    } catch (e) {
      debugPrint('VehiclesParkingService.updateVehicle error: $e');
      rethrow;
    }
  }

  /// Soft deletes the vehicle by setting status to inactive.
  Future<void> deactivateVehicle({
    required String vehicleId,
    required String societyId,
  }) async {
    if (_safeClient == null) {
      _societyVehicles.removeWhere((v) => v.id == vehicleId);
      notifyListeners();
      return;
    }

    try {
      await _client
          .from('vehicles')
          .update({'status': 'inactive', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', vehicleId);

      // If this vehicle was tied to an active slot allocation, unlink it so allocation stays at flat-level
      try {
        await _client
            .from('parking_allocations')
            .update({'vehicle_id': null, 'updated_at': DateTime.now().toIso8601String()})
            .eq('vehicle_id', vehicleId)
            .eq('status', 'active');
      } catch (_) {}

      await fetchSocietyVehicles(societyId: societyId);
    } catch (e) {
      debugPrint('VehiclesParkingService.deactivateVehicle error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 4. GATE SECURITY & LOGGING (Guard / Admin)
  // ─────────────────────────────────────────────────────────────

  Future<PlateLookupResult> lookupPlate({
    required String societyId,
    required String plateNumber,
  }) async {
    final clean = normalizePlate(plateNumber);

    // A gate verdict is a security decision. Only ever report "registered"
    // off a genuine match — never off the nearest sample row, and never
    // guess when the lookup itself failed.
    PlateLookupResult unregistered() => PlateLookupResult(
          found: false,
          matchStatus: MatchStatus.unregistered,
          normalizedQuery: clean,
        );

    if (_isOffline) {
      final matches = _mockVehicles()
          .where((v) => normalizePlate(v.vehicleNumber) == clean);
      if (matches.isEmpty) return unregistered();
      final match = matches.first;
      return PlateLookupResult(
        found: true,
        matchStatus: MatchStatus.registered,
        normalizedQuery: clean,
        vehicleId: match.id,
        vehicleNumber: match.vehicleNumber,
        makeModel: match.makeModel,
        color: match.color,
        type: match.type,
        flatId: match.flatId,
        flatNumber: match.flatNumber,
        blockName: match.blockName,
        residentName: match.residentName,
        residentPhone: match.residentPhone,
        slotNumber: match.allocatedSlotNumber,
        slotCategory: match.allocatedSlotCategory,
      );
    }

    if (societyId.isEmpty) {
      throw Exception('This account is not linked to a society yet.');
    }

    // Deliberately not caught: a failed lookup must reach the guard as an
    // error, not be rendered as "not registered".
    final rpcRes = await _client.rpc('lookup_vehicle_by_plate', params: {
      'p_society_id': societyId,
      'p_plate_number': clean,
    });

    if (rpcRes is Map) {
      // Since migration 17 the lookup refuses callers who are not a guard
      // or admin of this society. A refusal is not "not registered".
      if (rpcRes['success'] == false) {
        throw Exception(rpcRes['error']?.toString() ?? 'Lookup refused');
      }
      return PlateLookupResult.fromMap(Map<String, dynamic>.from(rpcRes), clean);
    }
    return unregistered();
  }

  Future<VehicleEntryLogItem> logGateEntry({
    required String societyId,
    required String plateNumber,
    String? vehicleId,
    required MatchStatus matchStatus,
    String? notes,
  }) async {
    final clean = normalizePlate(plateNumber);
    if (_isOffline) {
      final newLog = VehicleEntryLogItem(
        id: 'log-${DateTime.now().millisecondsSinceEpoch}',
        societyId: societyId,
        vehicleId: vehicleId,
        vehicleNumberEntered: clean,
        matchStatus: matchStatus,
        entryAt: DateTime.now(),
        notes: notes,
      );
      _recentLogs.insert(0, newLog);
      notifyListeners();
      return newLog;
    }

    if (societyId.isEmpty) {
      throw Exception('This account is not linked to a society yet.');
    }

    try {
      // Prefer the RPC: it stamps logged_by = auth.uid(), so the gate
      // register records which guard waved the vehicle through. A plain
      // insert leaves that column null and loses the audit trail.
      try {
        final rpcRes = await _client.rpc('log_vehicle_entry', params: {
          'p_society_id': societyId,
          'p_plate_number': clean,
          'p_vehicle_id': vehicleId,
          'p_match_status': matchStatus.toDbValue(),
          'p_notes': (notes != null && notes.isNotEmpty) ? notes : null,
        });

        if (rpcRes is Map && rpcRes['success'] == true) {
          await fetchGateLogs(societyId: societyId);
          final logId = rpcRes['log_id']?.toString();
          final match = _recentLogs.where((l) => l.id == logId);
          if (match.isNotEmpty) return match.first;
          return VehicleEntryLogItem(
            id: logId ?? '',
            societyId: societyId,
            vehicleId: vehicleId,
            vehicleNumberEntered: clean,
            matchStatus: matchStatus,
            entryAt: DateTime.now(),
            notes: notes,
          );
        }
      } on PostgrestException catch (rpcErr) {
        // Only fall through when the function is absent (older schema).
        if (rpcErr.code != '42883') rethrow;
        debugPrint('log_vehicle_entry RPC missing, inserting directly: $rpcErr');
      }

      final res = await _client.from('vehicle_entry_logs').insert({
        'society_id': societyId,
        'vehicle_id': ?vehicleId,
        'vehicle_number_entered': clean,
        'match_status': matchStatus.toDbValue(),
        'entry_at': DateTime.now().toIso8601String(),
        'logged_by': _client.auth.currentUser?.id,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }).select().single();

      final log = VehicleEntryLogItem.fromMap(res);
      await fetchGateLogs(societyId: societyId);
      return log;
    } catch (e) {
      debugPrint('VehiclesParkingService.logGateEntry error: $e');
      rethrow;
    }
  }

  Future<void> logGateExit({
    required String logId,
    required String societyId,
  }) async {
    if (_isOffline) {
      final idx = _recentLogs.indexWhere((l) => l.id == logId);
      if (idx != -1) {
        _recentLogs[idx] = VehicleEntryLogItem(
          id: _recentLogs[idx].id,
          societyId: _recentLogs[idx].societyId,
          vehicleId: _recentLogs[idx].vehicleId,
          vehicleNumberEntered: _recentLogs[idx].vehicleNumberEntered,
          matchStatus: _recentLogs[idx].matchStatus,
          entryAt: _recentLogs[idx].entryAt,
          exitAt: DateTime.now(),
          notes: _recentLogs[idx].notes,
        );
        notifyListeners();
      }
      return;
    }

    try {
      try {
        final rpcRes = await _client.rpc('log_vehicle_exit', params: {
          'p_log_id': logId,
          'p_society_id': societyId,
        });
        if (rpcRes is Map && rpcRes['success'] == true) {
          await fetchGateLogs(societyId: societyId);
          return;
        }
        if (rpcRes is Map && rpcRes['error'] != null) {
          // A real refusal (permission, missing log) — surface it rather
          // than retrying an update RLS will reject anyway.
          throw Exception(rpcRes['error']);
        }
      } on PostgrestException catch (rpcErr) {
        if (rpcErr.code != '42883') rethrow;
        debugPrint('log_vehicle_exit RPC missing, updating directly: $rpcErr');
      }

      await _client
          .from('vehicle_entry_logs')
          .update({'exit_at': DateTime.now().toIso8601String()})
          .eq('id', logId);
      await fetchGateLogs(societyId: societyId);
    } catch (e) {
      debugPrint('VehiclesParkingService.logGateExit error: $e');
      rethrow;
    }
  }

  /// Gate register. [todayOnly] keeps the guard's shift view honest — the
  /// screen labels this list "Today at the gate", so it must not quietly
  /// include last week's movements.
  Future<List<VehicleEntryLogItem>> fetchGateLogs({
    required String societyId,
    int limit = 100,
    bool todayOnly = true,
  }) async {
    if (_isOffline) {
      _recentLogs = _mockLogs();
      notifyListeners();
      return _recentLogs;
    }
    if (societyId.isEmpty) {
      _recentLogs = [];
      _setError('gateLogs', 'This account is not linked to a society yet.');
      notifyListeners();
      return _recentLogs;
    }

    try {
      var query = _client
          .from('vehicle_entry_logs')
          .select('''
            *,
            vehicles(
              make_model,
              flats(flat_number, blocks(name)),
              residents(full_name)
            )
          ''')
          .eq('society_id', societyId);

      if (todayOnly) {
        final now = DateTime.now();
        final startOfDay = DateTime(now.year, now.month, now.day);
        query = query.gte('entry_at', startOfDay.toIso8601String());
      }

      final res =
          await query.order('entry_at', ascending: false).limit(limit);

      final list = (res as List).cast<Map<String, dynamic>>();
      _recentLogs = list.map(VehicleEntryLogItem.fromMap).toList();
      _clearError('gateLogs');
      notifyListeners();
      return _recentLogs;
    } catch (e) {
      _recentLogs = [];
      _setError('gateLogs', e);
      notifyListeners();
      return _recentLogs;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 5. BAY REQUESTS (Resident raises, Society Admin reviews)
  // ─────────────────────────────────────────────────────────────

  static const _bayRequestSelect = '''
    *,
    flats(flat_number, blocks(name)),
    residents(full_name, phone),
    vehicles(vehicle_number, make_model, type)
  ''';

  /// Requests for the whole society (admin queue) or a single flat
  /// (resident's own view).
  Future<List<ParkingBayRequestItem>> fetchBayRequests({
    required String societyId,
    String? flatId,
    BayRequestStatus? status,
  }) async {
    if (_isOffline || societyId.isEmpty) {
      _bayRequests = [];
      notifyListeners();
      return _bayRequests;
    }

    try {
      var query = _client
          .from('parking_bay_requests')
          .select(_bayRequestSelect)
          .eq('society_id', societyId);

      if (flatId != null && flatId.isNotEmpty) {
        query = query.eq('flat_id', flatId);
      }
      if (status != null) {
        query = query.eq('status', status.toDbValue());
      }

      final res = await query.order('created_at', ascending: false);
      final list = (res as List).cast<Map<String, dynamic>>();
      _bayRequests = list.map(ParkingBayRequestItem.fromMap).toList();
      _clearError('bayRequests');
      notifyListeners();
      return _bayRequests;
    } catch (e) {
      _bayRequests = [];
      // An older database without migration 12 simply has no requests yet;
      // that is not worth showing the resident an error over.
      if (e is PostgrestException && (e.code == '42P01' || e.code == 'PGRST205')) {
        _clearError('bayRequests');
      } else {
        _setError('bayRequests', e);
      }
      notifyListeners();
      return _bayRequests;
    }
  }

  /// The one request a flat currently has awaiting review, if any.
  Future<ParkingBayRequestItem?> fetchMyPendingBayRequest({
    required String societyId,
    required String flatId,
  }) async {
    if (_isOffline || societyId.isEmpty || flatId.isEmpty) return null;
    try {
      final res = await _client
          .from('parking_bay_requests')
          .select(_bayRequestSelect)
          .eq('flat_id', flatId)
          .order('created_at', ascending: false)
          .limit(5);

      final list = (res as List).cast<Map<String, dynamic>>();
      final items = list.map(ParkingBayRequestItem.fromMap).toList();
      // Show the pending one if there is one, otherwise the most recent
      // decision so the resident learns it was declined.
      final pending = items.where((r) => r.isPending);
      if (pending.isNotEmpty) return pending.first;
      final rejected = items.where((r) => r.status == BayRequestStatus.rejected);
      if (rejected.isNotEmpty) return rejected.first;
      return null;
    } catch (e) {
      debugPrint('VehiclesParkingService.fetchMyPendingBayRequest error: $e');
      return null;
    }
  }

  Future<String> createBayRequest({
    required String societyId,
    required String flatId,
    String? residentId,
    String? vehicleId,
    SlotCategory? preferredCategory,
    String? notes,
  }) async {
    if (_isOffline) throw Exception('Not connected to the server.');
    if (societyId.isEmpty || flatId.isEmpty) {
      throw Exception('This account is not linked to a flat yet.');
    }

    final rpcRes = await _client.rpc('create_parking_bay_request', params: {
      'p_society_id': societyId,
      'p_flat_id': flatId,
      'p_resident_id': residentId,
      'p_vehicle_id': vehicleId,
      'p_preferred_category': preferredCategory?.toDbValue(),
      'p_notes': notes,
    });

    if (rpcRes is Map && rpcRes['success'] == true) {
      await fetchBayRequests(societyId: societyId, flatId: flatId);
      return rpcRes['request_id']?.toString() ?? '';
    }
    throw Exception(
      (rpcRes is Map ? rpcRes['error'] : null) ?? 'Could not submit the request',
    );
  }

  Future<void> reviewBayRequest({
    required String requestId,
    required String societyId,
    required BayRequestStatus action, // approved | rejected
    String? reviewNotes,
  }) async {
    if (_isOffline) throw Exception('Not connected to the server.');

    final rpcRes = await _client.rpc('review_parking_bay_request', params: {
      'p_request_id': requestId,
      'p_action': action.toDbValue(),
      'p_review_notes': reviewNotes,
    });

    if (rpcRes is Map && rpcRes['success'] == true) {
      await fetchBayRequests(societyId: societyId);
      return;
    }
    throw Exception(
      (rpcRes is Map ? rpcRes['error'] : null) ?? 'Could not update the request',
    );
  }

  Future<void> cancelBayRequest({
    required String requestId,
    required String societyId,
    String? flatId,
  }) async {
    if (_isOffline) throw Exception('Not connected to the server.');

    final rpcRes = await _client.rpc('cancel_parking_bay_request', params: {
      'p_request_id': requestId,
    });

    if (rpcRes is Map && rpcRes['success'] == true) {
      await fetchBayRequests(societyId: societyId, flatId: flatId);
      return;
    }
    throw Exception(
      (rpcRes is Map ? rpcRes['error'] : null) ?? 'Could not withdraw the request',
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 6. PARKING POLICY (Society Admin)
  // ─────────────────────────────────────────────────────────────

  Future<ParkingPolicyConfig> fetchParkingPolicy(String societyId) async {
    if (_safeClient == null) {
      _policyConfig = ParkingPolicyConfig(societyId: societyId);
      return _policyConfig!;
    }

    try {
      final res = await _client
          .from('parking_society_configs')
          .select()
          .eq('society_id', societyId)
          .maybeSingle();

      if (res != null) {
        _policyConfig = ParkingPolicyConfig.fromMap(res);
      } else {
        _policyConfig = ParkingPolicyConfig(societyId: societyId);
      }
      notifyListeners();
      return _policyConfig!;
    } catch (e) {
      debugPrint('VehiclesParkingService.fetchParkingPolicy error: $e');
      _policyConfig = ParkingPolicyConfig(societyId: societyId);
      return _policyConfig!;
    }
  }

  Future<void> updateParkingPolicy({
    required String societyId,
    required int maxSlotsPerFlat,
    required bool requireVehicleBinding,
  }) async {
    if (_safeClient == null) {
      _policyConfig = ParkingPolicyConfig(
        societyId: societyId,
        maxSlotsPerFlat: maxSlotsPerFlat,
        requireVehicleBinding: requireVehicleBinding,
      );
      notifyListeners();
      return;
    }

    try {
      await _client.from('parking_society_configs').upsert({
        'society_id': societyId,
        'max_slots_per_flat': maxSlotsPerFlat,
        'require_vehicle_binding': requireVehicleBinding,
        'updated_at': DateTime.now().toIso8601String(),
      });
      _policyConfig = ParkingPolicyConfig(
        societyId: societyId,
        maxSlotsPerFlat: maxSlotsPerFlat,
        requireVehicleBinding: requireVehicleBinding,
      );
      notifyListeners();
    } catch (e) {
      debugPrint('VehiclesParkingService.updateParkingPolicy error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SAMPLE DATA
  //
  // Used only when Supabase is not initialised at all (widget tests,
  // previews). Never used to paper over a failed query — see [_isOffline].
  // ─────────────────────────────────────────────────────────────

  List<ParkingSlotItem> _mockSlots() {
    return [
      ParkingSlotItem(
        id: 'slot-1',
        societyId: 'soc-1',
        slotNumber: 'P-101',
        vehicleType: VehicleType.fourWheeler,
        category: SlotCategory.covered,
        status: SlotStatus.allocated,
        blockName: 'Tower A',
        activeAllocation: const ActiveSlotAllocation(
          allocationId: 'alloc-1',
          flatId: 'f-101',
          flatNumber: 'A-101',
          blockName: 'Tower A',
          residentName: 'Abhishek Sharma',
          vehicleNumber: 'DL 03 CA 4589',
          vehicleMakeModel: 'Hyundai Creta',
        ),
      ),
      ParkingSlotItem(
        id: 'slot-2',
        societyId: 'soc-1',
        slotNumber: 'P-102',
        vehicleType: VehicleType.fourWheeler,
        category: SlotCategory.covered,
        status: SlotStatus.vacant,
        blockName: 'Tower A',
      ),
      ParkingSlotItem(
        id: 'slot-3',
        societyId: 'soc-1',
        slotNumber: 'P-103',
        vehicleType: VehicleType.twoWheeler,
        category: SlotCategory.open,
        status: SlotStatus.allocated,
        blockName: 'Tower B',
        activeAllocation: const ActiveSlotAllocation(
          allocationId: 'alloc-2',
          flatId: 'f-202',
          flatNumber: 'B-202',
          blockName: 'Tower B',
          residentName: 'Priya Patel',
          vehicleNumber: 'MH 12 BB 9988',
          vehicleMakeModel: 'Honda Activa 6G',
        ),
      ),
      ParkingSlotItem(
        id: 'slot-4',
        societyId: 'soc-1',
        slotNumber: 'P-104',
        vehicleType: VehicleType.fourWheeler,
        category: SlotCategory.open,
        status: SlotStatus.maintenance,
        blockName: 'Tower B',
      ),
      ParkingSlotItem(
        id: 'slot-5',
        societyId: 'soc-1',
        slotNumber: 'P-105',
        vehicleType: VehicleType.fourWheeler,
        category: SlotCategory.covered,
        status: SlotStatus.vacant,
        blockName: 'Tower C',
      ),
    ];
  }

  List<VehicleItem> _mockVehicles() {
    return [
      const VehicleItem(
        id: 'v1',
        societyId: 'soc-1',
        flatId: 'f-101',
        residentId: 'r-1',
        type: VehicleType.fourWheeler,
        vehicleNumber: 'DL03CA4589',
        makeModel: 'Hyundai Creta',
        color: 'Polar White',
        status: 'active',
        flatNumber: 'A-101',
        blockName: 'Tower A',
        residentName: 'Abhishek Sharma',
        residentPhone: '+91 98765 43210',
        allocatedSlotNumber: 'P-101',
        allocatedSlotCategory: SlotCategory.covered,
      ),
      const VehicleItem(
        id: 'v2',
        societyId: 'soc-1',
        flatId: 'f-202',
        residentId: 'r-2',
        type: VehicleType.twoWheeler,
        vehicleNumber: 'MH12BB9988',
        makeModel: 'Honda Activa 6G',
        color: 'Matte Grey',
        status: 'active',
        flatNumber: 'B-202',
        blockName: 'Tower B',
        residentName: 'Priya Patel',
        residentPhone: '+91 98111 22334',
        allocatedSlotNumber: 'P-103',
        allocatedSlotCategory: SlotCategory.open,
      ),
      const VehicleItem(
        id: 'v3',
        societyId: 'soc-1',
        flatId: 'f-303',
        residentId: 'r-3',
        type: VehicleType.fourWheeler,
        vehicleNumber: 'KA01MJ1122',
        makeModel: 'Kia Seltos',
        color: 'Gravity Grey',
        status: 'active',
        flatNumber: 'C-303',
        blockName: 'Tower C',
        residentName: 'Vikram Mehta',
        residentPhone: '+91 97222 33445',
        allocatedSlotNumber: null, // Waitlisted!
      ),
    ];
  }

  List<ParkingAllocationItem> _mockAllocations() {
    return [
      ParkingAllocationItem(
        id: 'alloc-1',
        societyId: 'soc-1',
        slotId: 'slot-1',
        flatId: 'f-101',
        residentId: 'r-1',
        allocatedFrom: DateTime.now().subtract(const Duration(days: 45)),
        status: AllocationStatus.active,
        slotNumber: 'P-101',
        slotCategory: SlotCategory.covered,
        flatNumber: 'A-101',
        blockName: 'Tower A',
        residentName: 'Abhishek Sharma',
        vehicleNumber: 'DL 03 CA 4589',
        vehicleMakeModel: 'Hyundai Creta',
      ),
      ParkingAllocationItem(
        id: 'alloc-2',
        societyId: 'soc-1',
        slotId: 'slot-3',
        flatId: 'f-202',
        residentId: 'r-2',
        allocatedFrom: DateTime.now().subtract(const Duration(days: 20)),
        status: AllocationStatus.active,
        slotNumber: 'P-103',
        slotCategory: SlotCategory.open,
        flatNumber: 'B-202',
        blockName: 'Tower B',
        residentName: 'Priya Patel',
        vehicleNumber: 'MH 12 BB 9988',
        vehicleMakeModel: 'Honda Activa 6G',
      ),
    ];
  }

  List<VehicleEntryLogItem> _mockLogs() {
    return [
      VehicleEntryLogItem(
        id: 'log-1',
        societyId: 'soc-1',
        vehicleNumberEntered: 'DL 03 CA 4589',
        matchStatus: MatchStatus.registered,
        entryAt: DateTime.now().subtract(const Duration(minutes: 15)),
        flatNumber: 'A-101',
        blockName: 'Tower A',
        residentName: 'Abhishek Sharma',
        makeModel: 'Hyundai Creta',
      ),
      VehicleEntryLogItem(
        id: 'log-2',
        societyId: 'soc-1',
        vehicleNumberEntered: 'UP 16 DX 9876',
        matchStatus: MatchStatus.unregistered,
        entryAt: DateTime.now().subtract(const Duration(minutes: 38)),
        notes: 'Uber Cab for B-202',
      ),
    ];
  }
}
