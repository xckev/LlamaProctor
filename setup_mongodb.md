# MongoDB Setup Guide for LlamaProctor

## Current Configuration

The app is pre-configured to use MongoDB Atlas with the following connection string:
```
mongodb+srv://xckevin2:eXOOgx5CMlnCLaui@cluster0.gcvor7r.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0
```

No additional setup is required - the app will automatically connect to the MongoDB Atlas cluster.

## Database Structure

The app uses:
- **Database**: `LlamaProctorDB`
- **Collection**: `students`

### Document Structure

Each student document contains:
```json
{
  "id": "1",
  "focus-score": 8,
  "description": "Student is working on math problems",
  "suggestion": "on-task",
  "classroom": "1",
  "active": true,
  "lastUpdated": 1640995200
}
```

## Testing the Connection

### Test with MongoDB Compass:
1. Download [MongoDB Compass](https://www.mongodb.com/products/compass)
2. Connect using the connection string above
3. Navigate to `LlamaProctorDB.students` collection
4. Verify documents are being created/updated

### Test with Command Line:
```bash
# Connect to the Atlas cluster
mongosh "mongodb+srv://xckevin2:eXOOgx5CMlnCLaui@cluster0.gcvor7r.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"

# Query the students collection
use LlamaProctorDB
db.students.find()
```

## Troubleshooting

### Common Issues:

1. **Network Access**: Ensure your IP is whitelisted in MongoDB Atlas
2. **Authentication**: The connection string includes credentials
3. **Permission Denied**: Make sure the app has necessary permissions

### Debug Mode:
The app logs MongoDB operations to the console. Check Xcode console for:
- `=== MONGODB OPERATION ===`
- `=== MONGODB QUERY ===`
- `=== MONGODB UPDATE ===`
- `MongoDB Service initialized with Atlas cluster`

## Security Best Practices

1. **Connection String**: The connection string is embedded in the app
2. **Network Security**: MongoDB Atlas provides SSL/TLS encryption
3. **Access Control**: Database access is controlled by Atlas user credentials
4. **Regular Backups**: Atlas provides automatic backups

## Alternative Setup Options

If you need to use a different MongoDB instance:

### Local MongoDB:
1. Install MongoDB locally
2. Update the `mongoURI` in `MongoDBService.swift`
3. Change to: `"mongodb://localhost:27017"`

### Different Atlas Cluster:
1. Create a new MongoDB Atlas cluster
2. Get your connection string from Atlas dashboard
3. Update the `mongoURI` in `MongoDBService.swift`
4. Replace with your new connection string 