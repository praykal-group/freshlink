import 'dart:io';

Stream<List<int>> openFileStream(String path) => File(path).openRead();
