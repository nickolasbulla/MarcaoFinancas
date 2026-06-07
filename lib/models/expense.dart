class Expense {
  final int? id;
  final String description;
  final double amount;
  final String category;
  final DateTime date;
  final DateTime createdAt;

  Expense({
    this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.date,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'description': description,
      'amount': amount,
      'category': category,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'],
      description: map['description'],
      amount: map['amount'],
      category: map['category'],
      date: DateTime.parse(map['date']),
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  @override
  String toString() =>
      'Expense(id: $id, description: $description, amount: $amount, category: $category, date: $date)';
}
