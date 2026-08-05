#!/bin/bash

# Deploy Yapp AI Edge Function to Supabase
# This script deploys the chat-with-nova edge function

echo "🚀 Deploying Yapp AI Edge Function..."

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Installing..."
    brew install supabase/tap/supabase
fi

# Check if logged in
if ! supabase projects list &> /dev/null; then
    echo "🔑 Please login to Supabase..."
    supabase login
fi

# Link project if not already linked
if [ ! -f ".git/config" ] || ! grep -q "supabase" ".git/config" 2>/dev/null; then
    echo "🔗 Linking to Supabase project..."
    supabase link --project-ref nfjlgqylmggppsxabtbd
fi

# Check if GEMINI_API_KEY is set
echo ""
echo "⚠️  Make sure you have set the GEMINI_API_KEY secret:"
echo "    supabase secrets set GEMINI_API_KEY=your_key_here"
echo ""
read -p "Press Enter to continue with deployment..."

# Deploy the function
echo "📦 Deploying chat-with-nova function..."
supabase functions deploy chat-with-nova

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    echo ""
    echo "Your Yapp AI is now live at:"
    echo "https://nfjlgqylmggppsxabtbd.supabase.co/functions/v1/chat-with-nova"
else
    echo "❌ Deployment failed. Please check the errors above."
    exit 1
fi
