/**
 * 家庭成员与角色。
 * 多终端协同的基础 —— 不同角色看到的内容与可执行的操作不同。
 */
export class FamilyMember {
  userId: string = '';
  name: string = '';
  /** 角色：child / grid_worker / property / maintainer */
  role: string = '';
  /** 角色中文名 */
  roleName: string = '';
  /** 手机号（脱敏展示） */
  phone: string = '';
  /** 是否可查看活动报告（隐私边界：仅直系家属） */
  canViewActivity: boolean = false;
  /** 是否可处置告警 */
  canHandle: boolean = false;
}

/** 家庭信息 */
export class Family {
  familyId: string = '';
  familyName: string = '';
  /** 老人姓名 */
  elderName: string = '';
  /** 老人年龄 */
  elderAge: number = 0;
  /** 家庭成员 */
  members: FamilyMember[] = [];
}

/** 当前登录用户 */
export class CurrentUser {
  userId: string = '';
  name: string = '';
  role: string = '';
  familyId: string = '';
  accessToken: string = '';

  /** 是否可查看活动报告 */
  canViewActivity(): boolean {
    return this.role === 'child';
  }

  /** 是否可处置告警 */
  canHandle(): boolean {
    return this.role !== 'maintainer';
  }
}
