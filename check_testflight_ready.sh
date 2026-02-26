#!/bin/bash

# TestFlight 发布准备检查脚本
# 用于验证所有前置条件是否满足

set -e

echo "======================================"
echo "  Kirole TestFlight 发布准备检查"
echo "======================================"
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_pass() {
    echo -e "${GREEN}✅ $1${NC}"
}

check_fail() {
    echo -e "${RED}❌ $1${NC}"
}

check_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 1. 检查 Xcode
echo "1. 检查 Xcode..."
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -1)
    check_pass "Xcode 已安装: $XCODE_VERSION"
else
    check_fail "Xcode 未安装"
    exit 1
fi
echo ""

# 2. 检查签名证书
echo "2. 检查签名证书..."
DEV_CERT=$(security find-identity -v -p codesigning | grep "Apple Development" | wc -l | tr -d ' ')
DIST_CERT=$(security find-identity -v -p codesigning | grep "Apple Distribution" | wc -l | tr -d ' ')

if [ "$DEV_CERT" -gt 0 ]; then
    check_pass "Development 证书: $DEV_CERT 个"
else
    check_fail "Development 证书: 未找到"
fi

if [ "$DIST_CERT" -gt 0 ]; then
    check_pass "Distribution 证书: $DIST_CERT 个"
else
    check_warn "Distribution 证书: 未找到(需要创建)"
    echo "   → 在 Xcode → Settings → Accounts → Manage Certificates 中创建"
fi
echo ""

# 3. 检查项目配置
echo "3. 检查项目配置..."
if [ -f "Config/Kirole.entitlements" ]; then
    check_pass "Entitlements 文件存在"

    if grep -q "com.apple.developer.family-controls" "Config/Kirole.entitlements"; then
        check_pass "Family Controls 权限已配置"
    else
        check_fail "Family Controls 权限未配置"
    fi
else
    check_fail "Entitlements 文件不存在"
fi

if [ -f "Config/Info.plist" ]; then
    check_pass "Info.plist 文件存在"

    if grep -q "NSFamilyControlsUsageDescription" "Config/Info.plist"; then
        check_pass "Family Controls 隐私说明已配置"
    else
        check_fail "Family Controls 隐私说明未配置"
    fi
else
    check_fail "Info.plist 文件不存在"
fi
echo ""

# 4. 检查构建配置
echo "4. 检查构建配置..."
if [ -d "Kirole.xcworkspace" ]; then
    check_pass "Workspace 文件存在"
else
    check_fail "Workspace 文件不存在"
    exit 1
fi

# 尝试构建(Debug 配置)
echo "   正在测试构建..."
if xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    -configuration Debug \
    build > /tmp/kirole_build.log 2>&1; then
    check_pass "Debug 构建成功"
else
    check_fail "Debug 构建失败"
    echo "   查看日志: /tmp/kirole_build.log"
fi
echo ""

# 5. 检查 Developer Portal 配置
echo "5. Developer Portal 配置检查..."
check_warn "需要手动验证以下项目:"
echo "   1. 访问 https://developer.apple.com/account/"
echo "   2. 登录 xiaoyouzi2010@gmail.com"
echo "   3. 进入 Certificates, Identifiers & Profiles"
echo "   4. 检查 com.kirole.app 是否存在"
echo "   5. 检查 Family Controls 是否已勾选"
echo ""

# 6. 检查 App Store Connect
echo "6. App Store Connect 配置检查..."
check_warn "需要手动验证以下项目:"
echo "   1. 访问 https://appstoreconnect.apple.com/"
echo "   2. 登录 xiaoyouzi2010@gmail.com"
echo "   3. 检查 Kirole App 是否已创建"
echo "   4. 如果未创建,按照 TESTFLIGHT_GUIDE.md 步骤 4 创建"
echo ""

# 7. 总结
echo "======================================"
echo "  检查总结"
echo "======================================"
echo ""

if [ "$DIST_CERT" -gt 0 ]; then
    echo -e "${GREEN}✅ 所有本地配置已就绪!${NC}"
    echo ""
    echo "下一步:"
    echo "1. 在 Developer Portal 启用 Family Controls"
    echo "2. 在 Xcode 刷新 Provisioning Profile"
    echo "3. 在 App Store Connect 创建 App(如果未创建)"
    echo "4. 执行 Archive 并上传"
    echo ""
    echo "详细步骤请参考: TESTFLIGHT_GUIDE.md"
else
    echo -e "${YELLOW}⚠️  需要创建 Distribution 证书${NC}"
    echo ""
    echo "创建步骤:"
    echo "1. 打开 Xcode"
    echo "2. Xcode → Settings → Accounts"
    echo "3. 选择 xiaoyouzi2010@gmail.com"
    echo "4. 点击 Manage Certificates"
    echo "5. 点击 + → Apple Distribution"
    echo ""
    echo "然后重新运行此脚本验证"
fi
echo ""
