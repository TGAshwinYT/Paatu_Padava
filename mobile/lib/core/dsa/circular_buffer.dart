import 'dart:collection';

/// High-Performance Fixed-Capacity O(1) Circular Ring Buffer.
/// 
/// Avoids repeated memory allocations by using a fixed-size internal array with head/tail pointers.
/// Ideal for sliding-window telemetry, audio latency monitoring, and bounded playback histories.
class CircularBuffer<T> with IterableMixin<T> {
  final int capacity;
  late final List<T?> _buffer;
  int _head = 0;
  int _tail = 0;
  int _count = 0;

  CircularBuffer(this.capacity) : assert(capacity > 0, 'Capacity must be greater than zero') {
    _buffer = List<T?>.filled(capacity, null);
  }

  /// Current number of elements stored.
  @override
  int get length => _count;

  /// Whether the buffer is full.
  bool get isFull => _count == capacity;

  /// Whether the buffer is empty.
  @override
  bool get isEmpty => _count == 0;

  /// Whether the buffer is non-empty.
  @override
  bool get isNotEmpty => _count > 0;

  /// Appends an item in O(1) time.
  /// If the buffer is full, overwrites the oldest element in O(1).
  void add(T item) {
    _buffer[_tail] = item;
    _tail = (_tail + 1) % capacity;

    if (_count == capacity) {
      _head = (_head + 1) % capacity; // Overwrote oldest item
    } else {
      _count++;
    }
  }

  /// Retrieves the element at [index] relative to the oldest element (0 = oldest) in O(1) time.
  T operator [](int index) {
    if (index < 0 || index >= _count) {
      throw RangeError.index(index, this, 'index');
    }
    final actualIndex = (_head + index) % capacity;
    return _buffer[actualIndex] as T;
  }

  /// Retrieves the newest element in O(1) time. Throws StateError if empty.
  @override
  T get last {
    if (_count == 0) throw StateError('No element');
    final lastIndex = (_tail - 1 + capacity) % capacity;
    return _buffer[lastIndex] as T;
  }

  /// Retrieves the newest element or null if empty.
  T? get lastOrNull {
    if (_count == 0) return null;
    final lastIndex = (_tail - 1 + capacity) % capacity;
    return _buffer[lastIndex];
  }

  /// Retrieves the oldest element in O(1) time. Throws StateError if empty.
  @override
  T get first {
    if (_count == 0) throw StateError('No element');
    return _buffer[_head] as T;
  }

  /// Retrieves the oldest element or null if empty.
  T? get firstOrNull {
    if (_count == 0) return null;
    return _buffer[_head];
  }

  /// Clears the buffer in O(1) pointer reset time.
  void clear() {
    _buffer.fillRange(0, capacity, null);
    _head = 0;
    _tail = 0;
    _count = 0;
  }

  /// Snapshot of elements in chronological order (oldest to newest).
  @override
  List<T> toList({bool growable = false}) {
    final list = List<T>.generate(_count, (i) => this[i], growable: growable);
    return list;
  }

  @override
  Iterator<T> get iterator => _CircularBufferIterator(this);
}

class _CircularBufferIterator<T> implements Iterator<T> {
  final CircularBuffer<T> _buffer;
  int _currentIndex = -1;

  _CircularBufferIterator(this._buffer);

  @override
  T get current {
    if (_currentIndex < 0 || _currentIndex >= _buffer.length) {
      throw StateError('Iterator out of bounds');
    }
    return _buffer[_currentIndex];
  }

  @override
  bool moveNext() {
    if (_currentIndex + 1 < _buffer.length) {
      _currentIndex++;
      return true;
    }
    return false;
  }
}
