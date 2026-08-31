import { ROUTE_PATH } from '#ui/constants';

/** Sidebar nav items with required RBAC permission code. */
export type NavItem = {
  href: string;
  label: string;
  permission: string;
};

export const ADMIN_NAV_ITEMS: NavItem[] = [
  { href: ROUTE_PATH.dashboard, label: '概览', permission: 'system:read' },
  { href: ROUTE_PATH.users, label: '用户管理', permission: 'user:read' },
  { href: ROUTE_PATH.roles, label: '角色权限', permission: 'permission:read' },
  { href: ROUTE_PATH.accounts, label: '账号管理', permission: 'account:read' },
  { href: ROUTE_PATH.rules, label: '自动回复', permission: 'rule:read' },
  { href: ROUTE_PATH.fans, label: '粉丝管理', permission: 'member:read' },
  { href: ROUTE_PATH.payments, label: '充值支付', permission: 'payment:read' },
  { href: ROUTE_PATH.modules, label: '模块管理', permission: 'module:read' },
  { href: ROUTE_PATH.cloud, label: '云服务', permission: 'cloud:read' },
  { href: ROUTE_PATH.logs, label: '消息日志', permission: 'message:read' },
  { href: ROUTE_PATH.materials, label: '素材库', permission: 'material:read' },
  { href: ROUTE_PATH.points, label: '积分商城', permission: 'points:read' },
  { href: ROUTE_PATH.menu, label: '公众号菜单', permission: 'menu:read' },
  { href: ROUTE_PATH.checkin, label: '签到记录', permission: 'checkin:read' },
  { href: ROUTE_PATH.luckyDraw, label: '大转盘抽奖', permission: 'lucky_draw:read' },
  { href: ROUTE_PATH.coupon, label: '优惠券', permission: 'coupon:read' },
  { href: ROUTE_PATH.vote, label: '投票', permission: 'vote:read' },
  { href: ROUTE_PATH.seckill, label: '秒杀', permission: 'seckill:read' },
  { href: ROUTE_PATH.memberCard, label: '会员卡', permission: 'member_card:read' },
  { href: ROUTE_PATH.shopAdmin, label: '商城运营', permission: 'shop:write' },
  { href: ROUTE_PATH.shopOrders, label: '订单管理', permission: 'shop:read' },
  { href: ROUTE_PATH.shop, label: '商城', permission: 'shop:read' },
  { href: ROUTE_PATH.distribution, label: '分销', permission: 'distribution:read' },
  { href: ROUTE_PATH.aiAdmin, label: 'AI 管理', permission: 'ai:read' },
  { href: ROUTE_PATH.auditLogs, label: '审计日志', permission: 'audit:read' },
  { href: ROUTE_PATH.mailTemplates, label: '邮件模板', permission: 'mail_template:read' },
  { href: ROUTE_PATH.tasks, label: '任务中心', permission: 'task:read' },
  { href: ROUTE_PATH.tenants, label: '租户管理', permission: 'tenant:read' },
];

/** Map route path → required read permission (for PermissionGate). Fallback when nav API unavailable. */
export const ROUTE_PERMISSIONS: Record<string, string> = {
  ...Object.fromEntries(ADMIN_NAV_ITEMS.map((item) => [item.href, item.permission])),
  '/dashboard': 'system:read',
  '/roles': 'permission:read',
  '/audit-logs': 'audit:read',
  '/mail-templates': 'mail_template:read',
  '/ai-admin': 'ai:read',
  '/ai-chat': 'ai:read',
  '/lucky-draw': 'lucky_draw:read',
  '/member-card': 'member_card:read',
  [ROUTE_PATH.aiChat]: 'ai:read',
  [ROUTE_PATH.files]: 'user:read',
};
