# Deploying Riesen ED Dashboard to Railway

## Prerequisites
1. Railway account (https://railway.app)
2. Railway CLI installed (optional but recommended)
3. GitHub repository connected to Railway

## Required Environment Variables

### Critical Variables (Must Set)

1. **RAILS_MASTER_KEY**
   - Get from: `config/master.key`
   - This is required to decrypt Rails credentials
   - ⚠️ Never commit this to your repository

2. **DATABASE_URL**
   - Railway automatically provides this when you provision PostgreSQL
   - Format: `postgresql://user:password@host:5432/database`

3. **SECRET_KEY_BASE**
   - Generate with: `rails secret`
   - Used for session encryption

### Recommended Variables

```env
RAILS_ENV=production
RACK_ENV=production
NODE_ENV=production
PORT=${{PORT}}  # Railway provides this
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
RAILS_HOSTS=your-app.up.railway.app
```

## Deployment Steps

### 1. Prepare Your Application

```bash
# Ensure your local master key is present
cat config/master.key

# Test production build locally
RAILS_ENV=production bundle exec rails assets:precompile
RAILS_ENV=production bundle exec rails db:create db:migrate
```

### 2. Set Up Railway Project

1. Create new project on Railway
2. Add PostgreSQL service
3. Connect your GitHub repository

### 3. Configure Environment Variables

In Railway dashboard:
1. Go to your service settings
2. Click on "Variables"
3. Add the following:

```env
RAILS_MASTER_KEY=<your_master_key_from_config/master.key>
SECRET_KEY_BASE=<generate_with_rails_secret>
RAILS_ENV=production
RACK_ENV=production
NODE_ENV=production
RAILS_LOG_TO_STDOUT=true
RAILS_SERVE_STATIC_FILES=true
RAILS_HOSTS=<your-railway-domain>
```

### 4. Deploy

Railway will automatically deploy when you:
- Push to your connected GitHub branch
- Or manually trigger deployment in Railway dashboard

### 5. Run Database Migrations

After first deployment:

```bash
# Using Railway CLI
railway run rails db:migrate

# Or in Railway dashboard
# Go to your service > Settings > Deploy > Run command
# Enter: rails db:migrate
```

### 6. Seed Database (Optional)

```bash
railway run rails db:seed
```

## Troubleshooting

### Common Issues

1. **Assets not loading**
   - Ensure `RAILS_SERVE_STATIC_FILES=true`
   - Check `rails assets:precompile` succeeded

2. **Database connection failed**
   - Verify DATABASE_URL is set correctly
   - Check PostgreSQL service is running

3. **Application crashes on start**
   - Check logs in Railway dashboard
   - Verify RAILS_MASTER_KEY is correct
   - Ensure all migrations ran successfully

4. **Blocked host error**
   - Add your Railway domain to RAILS_HOSTS
   - Or update `config/environments/production.rb`

### Viewing Logs

```bash
# Using Railway CLI
railway logs

# Or view in Railway dashboard under Deployments > View Logs
```

## Production Checklist

- [ ] RAILS_MASTER_KEY is set
- [ ] SECRET_KEY_BASE is generated and set
- [ ] Database is provisioned and DATABASE_URL is set
- [ ] RAILS_HOSTS includes your Railway domain
- [ ] Assets precompile successfully
- [ ] Database migrations run successfully
- [ ] Application starts without errors
- [ ] Can access the application at your Railway URL

## Security Notes

1. Never commit `config/master.key` to version control
2. Use strong SECRET_KEY_BASE (generate with `rails secret`)
3. Consider adding basic authentication in production:
   ```ruby
   # In ApplicationController
   http_basic_authenticate_with name: ENV['BASIC_AUTH_USERNAME'], 
                                password: ENV['BASIC_AUTH_PASSWORD'] if Rails.env.production?
   ```
4. Enable FORCE_SSL in production for HTTPS enforcement

## Monitoring

Railway provides:
- Deployment logs
- Runtime logs
- Metrics (CPU, Memory, Network)
- Crash notifications

Access these in your Railway project dashboard.