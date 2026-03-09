import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    String path = join(await getDatabasesPath(), 'offline_wallet.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE transactions(
            id TEXT PRIMARY KEY,
            amount REAL,
            sender TEXT,
            receiver TEXT
          )
        ''');
      },
    );
  }

  // 1. Save a transaction when offline
  static Future<void> saveOfflineTransaction({
    required String transactionId,
    required double amount,
    required String sender,
    required String receiver,
  }) async {
    final db = await database;
    await db.insert('transactions', {
      'id': transactionId,
      'amount': amount,
      'sender': sender,
      'receiver': receiver,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // 2. Fetch all offline transactions
  static Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    final db = await database;
    return await db.query('transactions');
  }

  // 3. Delete a transaction once it successfully syncs
  static Future<void> deleteTransaction(String transactionId) async {
    final db = await database;
    await db.delete(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );
  }
}
