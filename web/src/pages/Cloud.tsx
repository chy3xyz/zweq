import { Show, createSignal } from 'solid-js';

import {
  generateLicense,
  installPackage,
  listLicenses,
  listMarket,
  publishPackage,
  revokeLicense,
  toApiError,
  verifyLicense,
  type LicenseItem,
  type MarketItem,
} from '#ui/api';
import AccountRequiredBanner from '#ui/components/AccountRequiredBanner';
import AdminCrudPage from '#ui/components/AdminCrudPage';
import DataTable, { type Column } from '#ui/components/DataTable';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';
import Tabs from '#ui/components/Tabs';
import { useAccountId, useFeedback, usePaged } from '#ui/hooks';
import { formatDateTime } from '#ui/utils';

const TABS = ['授权码管理', '应用市场'] as const;
type Tab = (typeof TABS)[number];

const PAGE_SIZE = 20;

interface MarketFormState {
  name: string;
  title: string;
  version: string;
  download_url: string;
  description: string;
}

function Cloud() {
  const feedback = useFeedback();
  const { accountId, ready } = useAccountId();
  const [tab, setTab] = createSignal<Tab>('授权码管理');

  const licenses = usePaged<LicenseItem>((page, pageSize) => listLicenses(page, pageSize), PAGE_SIZE);
  const market = usePaged<MarketItem>((page, pageSize) => listMarket(page, pageSize), PAGE_SIZE);

  // License generate modal
  const [licenseModalOpen, setLicenseModalOpen] = createSignal(false);
  const [licenseDays, setLicenseDays] = createSignal(365);
  const [licenseSubmitting, setLicenseSubmitting] = createSignal(false);
  const [licenseError, setLicenseError] = createSignal<string | null>(null);

  const openLicenseModal = () => {
    setLicenseDays(365);
    setLicenseError(null);
    setLicenseModalOpen(true);
  };

  const onGenerateLicense = async (e: SubmitEvent) => {
    e.preventDefault();
    if (licenseSubmitting()) return;
    setLicenseSubmitting(true);
    setLicenseError(null);
    try {
      const lic = await generateLicense({ days: licenseDays() });
      setLicenseModalOpen(false);
      feedback.toast(`授权码已生成：${lic.license_key}`, 'success');
      void licenses.reload(1);
    } catch (err) {
      setLicenseError(toApiError(err).message);
    } finally {
      setLicenseSubmitting(false);
    }
  };

  // License verify modal
  const [verifyModalOpen, setVerifyModalOpen] = createSignal(false);
  const [verifyKey, setVerifyKey] = createSignal('');
  const [verifyResult, setVerifyResult] = createSignal<string | null>(null);
  const [verifySubmitting, setVerifySubmitting] = createSignal(false);

  const openVerifyModal = () => {
    setVerifyKey('');
    setVerifyResult(null);
    setVerifyModalOpen(true);
  };

  const onVerifyLicense = async (e: SubmitEvent) => {
    e.preventDefault();
    if (verifySubmitting()) return;
    setVerifySubmitting(true);
    try {
      const res = await verifyLicense({ key: verifyKey().trim() });
      setVerifyResult(res.valid ? '✓ 有效' : `✗ 无效（${res.reason}）`);
    } catch (err) {
      setVerifyResult(`✗ ${toApiError(err).message}`);
    } finally {
      setVerifySubmitting(false);
    }
  };

  const onRevokeLicense = (lic: LicenseItem) =>
    feedback.runAction({
      confirm: {
        title: '撤销授权码',
        message: `确定撤销授权码 ${lic.license_key} 吗？`,
        danger: true,
      },
      action: () => revokeLicense(lic.id),
      success: '授权码已撤销',
      onDone: () => void licenses.refresh(),
    });

  // Market publish modal
  const [marketModalOpen, setMarketModalOpen] = createSignal(false);
  const [marketForm, setMarketForm] = createSignal<MarketFormState>({
    name: '',
    title: '',
    version: '1.0.0',
    download_url: '',
    description: '',
  });
  const [marketSubmitting, setMarketSubmitting] = createSignal(false);
  const [marketError, setMarketError] = createSignal<string | null>(null);

  const openMarketModal = () => {
    setMarketForm({ name: '', title: '', version: '1.0.0', download_url: '', description: '' });
    setMarketError(null);
    setMarketModalOpen(true);
  };

  const setMarketField = <K extends keyof MarketFormState>(key: K, value: MarketFormState[K]) => {
    setMarketForm((prev) => ({ ...prev, [key]: value }));
  };

  const onPublishPackage = async (e: SubmitEvent) => {
    e.preventDefault();
    if (marketSubmitting()) return;
    setMarketSubmitting(true);
    setMarketError(null);
    try {
      const form = marketForm();
      await publishPackage({
        name: form.name.trim(),
        title: form.title.trim(),
        version: form.version.trim(),
        description: form.description.trim(),
        download_url: form.download_url.trim(),
      });
      setMarketModalOpen(false);
      feedback.toast('市场包已发布', 'success');
      void market.reload(1);
    } catch (err) {
      setMarketError(toApiError(err).message);
    } finally {
      setMarketSubmitting(false);
    }
  };

  const onInstallPackage = (pkg: MarketItem) => {
    if (!ready()) {
      feedback.toast('请先在右上角选择公众号', 'error');
      return;
    }
    void feedback.runAction({
      confirm: {
        title: '安装应用包',
        message: `安装市场包「${pkg.title}」到账号 ${accountId()} 吗？`,
      },
      action: () => installPackage(pkg.name, { account_id: accountId() }),
      success: `已安装 ${pkg.name} → 模块注册表 + 账号绑定`,
      onDone: () => void market.refresh(),
    });
  };

  const licenseColumns: Column<LicenseItem>[] = [
    { key: 'license_key', title: '授权码', render: (l) => <span class="font-mono text-xs">{l.license_key}</span> },
    {
      key: 'status',
      title: '状态',
      render: (l) => (
        <span class={`badge badge-sm ${l.status === 'active' ? 'badge-success' : l.status === 'expired' ? 'badge-warning' : 'badge-error'}`}>
          {l.status}
        </span>
      ),
    },
    { key: 'expires_at', title: '到期', render: (l) => <span class="text-sm text-base-content/70">{formatDateTime(l.expires_at)}</span> },
  ];

  const marketColumns: Column<MarketItem>[] = [
    { key: 'name', title: '包名', render: (m) => <span class="font-mono text-xs">{m.name}</span> },
    { key: 'title', title: '名称', render: (m) => <span class="font-medium">{m.title}</span> },
    { key: 'version', title: '版本', render: (m) => <span class="badge badge-sm badge-ghost">{m.version}</span> },
    {
      key: 'updated_at',
      title: '更新时间',
      render: (m) => <span class="text-sm text-base-content/70">{formatDateTime(m.updated_at)}</span>,
    },
  ];

  return (
    <div class="space-y-4">
      <div>
        <h2 class="text-xl font-semibold">云服务</h2>
        <p class="text-sm text-base-content/60">站点授权码 + 应用市场</p>
      </div>

      <AccountRequiredBanner />

      <Tabs tabs={[...TABS]} active={tab()} onChange={setTab} />

      <Show when={tab() === '授权码管理'}>
        <AdminCrudPage
          title="授权码管理"
          description="生成与管理站点授权码"
          total={licenses.total()}
          onCreate={openLicenseModal}
          createLabel="生成授权码"
          onRefresh={() => void licenses.refresh()}
          extra={
            <button type="button" class="btn btn-outline btn-sm" onClick={openVerifyModal}>
              校验授权码
            </button>
          }
        >
          <DataTable
            columns={licenseColumns}
            rows={licenses.items()}
            rowKey={(l) => l.id}
            total={licenses.total()}
            page={licenses.page()}
            totalPages={licenses.totalPages()}
            pageSize={licenses.pageSize()}
            loading={licenses.loading()}
            error={licenses.error()}
            emptyText="暂无授权码"
            onPageChange={(p) => void licenses.reload(p)}
            onPageSizeChange={(size) => licenses.setPageSize(size)}
            actions={(l) =>
              l.status === 'active' ? (
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onRevokeLicense(l)}>
                  撤销
                </button>
              ) : undefined
            }
          />
        </AdminCrudPage>
      </Show>

      <Show when={tab() === '应用市场'}>
        <AdminCrudPage
          title="应用市场"
          description="发布与管理应用市场包"
          total={market.total()}
          onCreate={openMarketModal}
          createLabel="发布应用包"
          onRefresh={() => void market.refresh()}
        >
          <DataTable
            columns={marketColumns}
            rows={market.items()}
            rowKey={(m) => m.id}
            total={market.total()}
            page={market.page()}
            totalPages={market.totalPages()}
            pageSize={market.pageSize()}
            loading={market.loading()}
            error={market.error()}
            emptyText="暂无市场包"
            onPageChange={(p) => void market.reload(p)}
            onPageSizeChange={(size) => market.setPageSize(size)}
            actions={(pkg) => (
              <button type="button" class="btn btn-primary btn-xs" onClick={() => onInstallPackage(pkg)}>
                安装
              </button>
            )}
          />
        </AdminCrudPage>
      </Show>

      <FormModal
        open={licenseModalOpen()}
        title="生成授权码"
        onSubmit={onGenerateLicense}
        onClose={() => setLicenseModalOpen(false)}
        submitting={licenseSubmitting()}
        error={licenseError()}
        size="sm"
      >
        <FormField label="有效天数" required>
          <input
            type="number"
            class="input input-bordered input-sm w-full"
            value={licenseDays()}
            onInput={(e) => setLicenseDays(Number(e.currentTarget.value))}
            min={1}
            required
          />
        </FormField>
      </FormModal>

      <FormModal
        open={verifyModalOpen()}
        title="校验授权码"
        onSubmit={onVerifyLicense}
        onClose={() => setVerifyModalOpen(false)}
        submitting={verifySubmitting()}
        size="sm"
      >
        <FormField label="授权码" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="WEQ-XXXXXXXX-XXXXXXXX-XXXXXXXX"
            value={verifyKey()}
            onInput={(e) => setVerifyKey(e.currentTarget.value)}
            required
          />
        </FormField>
        <Show when={verifyResult()}>
          <p class="text-sm">{verifyResult()}</p>
        </Show>
      </FormModal>

      <FormModal
        open={marketModalOpen()}
        title="发布应用包"
        onSubmit={onPublishPackage}
        onClose={() => setMarketModalOpen(false)}
        submitting={marketSubmitting()}
        error={marketError()}
        size="md"
      >
        <FormField label="包名" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="shop"
            value={marketForm().name}
            onInput={(e) => setMarketField('name', e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="名称" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="商城"
            value={marketForm().title}
            onInput={(e) => setMarketField('title', e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="版本">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            value={marketForm().version}
            onInput={(e) => setMarketField('version', e.currentTarget.value)}
          />
        </FormField>
        <FormField label="下载地址" required>
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="https://"
            value={marketForm().download_url}
            onInput={(e) => setMarketField('download_url', e.currentTarget.value)}
            required
          />
        </FormField>
        <FormField label="描述" required>
          <textarea
            class="textarea textarea-bordered w-full text-sm"
            rows={3}
            placeholder="应用包功能描述"
            value={marketForm().description}
            onInput={(e) => setMarketField('description', e.currentTarget.value)}
            required
          />
        </FormField>
      </FormModal>
    </div>
  );
}

export default Cloud;
