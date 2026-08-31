export const fenToYuan = (fen: number) => (fen / 100).toFixed(2);

export const yuanToFen = (yuan: number) => Math.round(yuan * 100);

export const formatYuan = (fen: number) => `¥${fenToYuan(fen)}`;
