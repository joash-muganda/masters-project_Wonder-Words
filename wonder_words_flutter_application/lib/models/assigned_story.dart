class AssignedStory {
  final String id;
  final String conversationId;
  final String title;
  final DateTime assignedAt;
  final String preview;

  AssignedStory({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.assignedAt,
    required this.preview,
  });

  factory AssignedStory.fromJson(Map<String, dynamic> json) {
    return AssignedStory(
      id: json['id'].toString(),
      conversationId: json['conversation_id'].toString(),
      title: json['title'],
      assignedAt: DateTime.parse(json['assigned_at']),
      preview: json['preview'],
    );
  }
}

class StoryTheme {
  final String id;
  final String name;
  final String iconName;
  final String colorHex;

  StoryTheme({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorHex,
  });

  factory StoryTheme.fromJson(Map<String, dynamic> json) {
    return StoryTheme(
      id: json['id'],
      name: json['name'],
      iconName: json['icon_name'],
      colorHex: json['color_hex'],
    );
  }
}
