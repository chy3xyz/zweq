import { For, Show, createSignal } from 'solid-js';

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
import DataTable, { type Column } from '#ui/components/DataTable';
import { useAccounts } from '#ui/hooks/useAccounts';
import { usePaged } from '#ui/hooks/usePaged';
import { formatDateTime } from '#ui/utils';

const PAGE_SIZE = 20;

function Cloud() {
  const accounts = useAccounts();
  const [success, setSuccess] = createSignal<string | null>(null);
  const [days, setDays] = createSignal(365);
  const [verifyKey, setVerifyKey] = createSignal('');
  const [verifyResult, setVerifyResult] = createSignal<string | null>(null);

  const [pkgName, setPkgName] = createSignal('');
  const [pkgTitle, setPkgTitle] = createSignal('');
  const [pkgVersion, setPkgVersion] = createSignal('1.0.0');
  const [pkgUrl, setPkgUrl] = createSignal('');

  const licenses = usePaged<LicenseItem>((page, pageSize) => listLicenses(page, pageSize), PAGE_SIZE);
  const market = usePaged<MarketItem>((page, pageSize) => listMarket(page, pageSize), PAGE_SIZE);
  const accountId = () => accounts.selected() ?? 0;

  const onGenerate = async (e: SubmitEvent) => {
    e.preventDefault();
    setSuccess(null);
    try {
      const lic = await generateLicense({ days: days() });
      setSuccess(`授权码已生成：${lic.license_key}`);
      void licenses.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onVerify = async (e: SubmitEvent) => {
    e.preventDefault();
    try {
      const res = await verifyLicense({ key: verifyKey().trim() });
      setVerifyResult(res.valid ? '✓ 有效' : `✗ 无效（${res.reason}）`);
    } catch (err) {
      setVerifyResult(`✗ ${toApiError(err).message}`);
    }
  };

  const onRevoke = async (lic: LicenseItem) => {
    if (!window.confirm(`确定撤销授权码 ${lic.license_key} 吗？`)) return;
    try {
      await revokeLicense(lic.id);
      void licenses.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onPublish = async (e: SubmitEvent) => {
    e.preventDefault();
    setSuccess(null);
    try {
      await publishPackage({
        name: pkgName().trim(),
        title: pkgTitle().trim(),
        version: pkgVersion().trim(),
        description: pkgTitle().trim(),
        download_url: pkgUrl().trim(),
      });
      setPkgName('');
      setPkgTitle('');
      setPkgUrl('');
      setSuccess('市场包已发布');
      void market.reload(1);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onInstall = async (pkg: MarketItem) => {
    if (accountId() === 0) {
      window.alert('请先选择账号');
      return;
    }
    if (!window.confirm(`安装市场包「${pkg.title}」到账号 ${accountId()} 吗？`)) return;
    try {
      await installPackage(pkg.name, { account_id: accountId() });
      setSuccess(`已安装 ${pkg.name} → 模块注册表 + 账号绑定`);
      void market.reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const licenseColumns: Column<LicenseItem>[] = [
    { key: 'license_key', title: '授权码', render: (l) => <span class="font-mono text-xs">{l.license_key}</span> },
    {
      key: 'status',
      title: '状态',
      render: (l) => (
        <span class={`badge badge-sm ${l.status === 'active' ? 'badge-success' : l.status === 'expired' ? 'badge-warning' : 'badge-error'}`}>{l.status}</span>
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

      <label class="form-control w-full max-w-xs">
        <span class="label-text mb-1">安装目标账号</span>
        <select class="select select-bordered select-sm" value={accountId()} onChange={(e) => accounts.setSelected(Number(e.currentTarget.value))}>
          <For each={accounts.accounts()}>
            {(a) => (
              <option value={a.id}>
                {a.name}（{a.id}）
              </option>
            )}
          </For>
        </select>
      </label>

      <Show when={success()}>
        <div role="alert" class="alert alert-success py-2 text-sm">
          {success()}
        </div>
      </Show>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
          <span class="text-sm font-semibold">授权码</span>
          <form onSubmit={onGenerate} class="flex items-end gap-2">
            <label class="form-control">
              <span class="label-text mb-1">有效天数</span>
              <input type="number" class="input input-bordered input-sm w-28" value={days()} onInput={(e) => setDays(Number(e.currentTarget.value))} min={1} required />
            </label>
            <button type="submit" class="btn btn-primary btn-sm">生成授权码</button>
          </form>
          <form onSubmit={onVerify} class="flex items-end gap-2">
            <label class="form-control flex-1">
              <span class="label-text mb-1">校验授权码</span>
              <input type="text" class="input input-bordered input-sm" placeholder="WEQ-XXXXXXXX-XXXXXXXX-XXXXXXXX" value={verifyKey()} onInput={(e) => setVerifyKey(e.currentTarget.value)} />
            </label>
            <button type="submit" class="btn btn-outline btn-sm">校验</button>
          </form>
          <Show when={verifyResult()}>
            <p class="text-sm">{verifyResult()}</p>
          </Show>
          <DataTable
            columns={licenseColumns}
            rows={licenses.items()}
            rowKey={(l) => l.id}
            total={licenses.total()}
            page={licenses.page()}
            totalPages={licenses.totalPages()}
            loading={licenses.loading()}
            error={licenses.error()}
            emptyText="暂无授权码"
            onPageChange={(p) => void licenses.reload(p)}
            actions={(l) =>
              l.status === 'active' ? (
                <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => onRevoke(l)}>
                  撤销
                </button>
              ) : undefined
            }
          />
        </div>

        <div class="rounded-lg border border-base-300 bg-base-200/40 p-4 space-y-3">
          <span class="text-sm font-semibold">应用市场</span>
          <form onSubmit={onPublish} class="flex items-end gap-2">
            <input type="text" class="input input-bordered input-sm w-24" placeholder="包名" value={pkgName()} onInput={(e) => setPkgName(e.currentTarget.value)} required />
            <input type="text" class="input input-bordered input-sm w-28" placeholder="名称" value={pkgTitle()} onInput={(e) => setPkgTitle(e.currentTarget.value)} required />
            <input type="text" class="input input-bordered input-sm w-24" value={pkgVersion()} onInput={(e) => setPkgVersion(e.currentTarget.value)} />
            <input type="text" class="input input-bordered input-sm flex-1" placeholder="下载地址" value={pkgUrl()} onInput={(e) => setPkgUrl(e.currentTarget.value)} />
            <button type="submit" class="btn btn-primary btn-sm">发布</button>
          </form>
          <DataTable
            columns={marketColumns}
            rows={market.items()}
            rowKey={(m) => m.id}
            total={market.total()}
            page={market.page()}
            totalPages={market.totalPages()}
            loading={market.loading()}
            error={market.error()}
            emptyText="暂无市场包"
            onPageChange={(p) => void market.reload(p)}
            actions={(pkg) => (
              <button type="button" class="btn btn-primary btn-xs" onClick={() => onInstall(pkg)}>
                安装
              </button>
            )}
          />
        </div>
      </div>
    </div>
  );
}

export default Cloud;
