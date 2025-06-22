# LlamaProctor

A macOS application that monitors student activity during class using AI analysis and stores the data in MongoDB.

## Features

- Real-time screen capture and analysis
- AI-powered activity monitoring using Llama 4
- MongoDB integration for data storage
- Focus score tracking based on AI analysis
- Active/inactive status tracking

## MongoDB Integration

The app stores student activity data in a MongoDB collection called `LlamaProctorDB.students`. Each document contains:

```json
{
  "id": "1",
  "focus-score": 8,
  "description": "Student is working on math problems in Google Docs",
  "suggestion": "on-task",
  "classroom": "1",
  "active": true,
  "lastUpdated": 1640995200
}
```

### Focus Score Logic

The focus score (0-10) is updated based on Llama 4's analysis:
- If Llama score ≤ 2: Decrease focus score by 1 (minimum 0)
- If Llama score ≥ 4: Increase focus score by 1 (maximum 10)
- If Llama score = 3: Keep focus score unchanged

## Setup

### MongoDB Configuration

1. Copy `Config.template.swift` to `LlamaProctor/Config.swift`
2. Replace the placeholder MongoDB URI with your actual connection string
3. The `Config.swift` file is gitignored to keep your credentials secure

### Building and Running

1. Open `LlamaProctor.xcodeproj` in Xcode
2. Build and run the project
3. Grant screen recording permissions when prompted
4. Enter a task description and the app will start monitoring

## Current Implementation

The current implementation includes:
- MongoDB service class with simulated operations
- Secure configuration management
- Focus score calculation logic
- Active/inactive status tracking
- Integration with the existing Llama 4 analysis

## Future Enhancements

- Real MongoDB integration using the MongoDB Swift driver
- Real-time database updates
- Multiple student support
- Teacher dashboard
- Historical data analysis

## Privacy and Security

- Screen capture data is processed locally and not stored
- Only analysis results are sent to MongoDB
- MongoDB credentials are stored in a gitignored configuration file
- Template file provided for easy setup without exposing credentials