#!/bin/bash

echo "======================================"
echo "  验证 Family Controls 配置"
echo "======================================"
echo ""

# 1. 检查 entitlements
echo "1. 检查 entitlements 文件..."
if grep -q "com.apple.developer.family-controls" Config/Kirole.entitlements; then
    echo "   ✅ Family Controls 权限已配置"
else
    echo "   ❌ Family Controls 权限未配置"
fi
echo ""

# 2. 检查 Provisioning Profiles
echo "2. 检查 Provisioning Profiles..."
PROFILE_DIR=~/Library/MobileDevice/Provisioning\ Profiles

if [ -d "$PROFILE_DIR" ]; then
    PROFILE_COUNT=$(find "$PROFILE_DIR" -name "*.mobileprovision" 2>/dev/null | wc -l | tr -d ' ')
    echo "   找到 $PROFILE_COUNT 个 Provisioning Profiles"

    if [ "$PROFILE_COUNT" -gt 0 ]; then
        # 检查是否有包含 Family Controls 的 Profile
        FC_PROFILE_COUNT=$(find "$PROFILE_DIR" -name "*.mobileprovision" -exec grep -l "family-controls" {} \; 2>/dev/null | wc -l | tr -d ' ')

        if [ "$FC_PROFILE_COUNT" -gt 0 ]; then
            echo "   ✅ 找到 $FC_PROFILE_COUNT 个包含 Family Controls 的 Profile"
        else
            echo "   ❌ 没有找到包含 Family Controls 的 Profile"
            echo "   → 需要在 Developer Portal 启用 Family Controls"
        fi
    else
        echo "   ⚠️  没有 Provisioning Profiles"
        echo "   → 在 Xcode 中下载: Settings → Accounts → Download Manual Profiles"
    fi
else
    echo "   ⚠️  Provisioning Profiles 目录不存在"
fi
echo ""

# 3. 检查项目配置
echo "3. 检查 Xcode 项目配置..."
if [ -f "Kirole.xcodeproj/project.pbxproj" ]; then
    if grep -q "com.apple.developer.family-controls" Kirole.xcodeproj/project.pbxproj; then
        echo "   ✅ 项目文件包含 Family Controls 配置"
    else
        echo "   ⚠️  项目文件可能缺少 Family Controls 配置"
    fi
else
    echo "   ❌ 项目文件不存在"
fi
echo ""

# 4. 提示下一步
echo "======================================"
echo "  下一步操作"
echo "======================================"
echo ""

if [ "$FC_PROFILE_COUNT" -gt 0 ] 2>/dev/null; then
    echo "✅ 配置完成!可以开始 Archive"
    echo ""
    echo "执行:"
    echo "1. 在 Xcode 中选择 'Any iOS Device (arm64)'"
    echo "2. Product → Clean Build Folder (⇧⌘K)"
    echo "3. Product → Archive"
else
    echo "⚠️  需要完成以下步骤:"
    echo ""
    echo "1. 访问 https://developer.apple.com/account/"
    echo "2. 登录 xiaoyouzi2010@gmail.com"
    echo "3. Certificates, Identifiers & Profiles → Identifiers"
    echo "4. 找到 com.kirole.app"
    echo "5. 勾选 Family Controls → Save"
    echo "6. 返回 Xcode → Settings → Accounts → Download Manual Profiles"
    echo "7. 重新生成 Provisioning Profile"
    echo "8. 重新 Archive"
fi
echo ""
