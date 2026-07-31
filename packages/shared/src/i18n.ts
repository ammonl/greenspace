import type { Language } from "./enums.js";

/**
 * i18n key contracts for Danish and English.
 * Keys are organized by domain area.
 * Actual translated strings live in the web app; this contract
 * ensures both apps reference the same set of keys.
 */
export const I18N_KEYS = {
  common: {
    appName: "common.appName",
    language: "common.language",
    submit: "common.submit",
    cancel: "common.cancel",
    confirm: "common.confirm",
    close: "common.close",
    loading: "common.loading",
    error: "common.error",
  },
  status: {
    preOpenTitle: "status.preOpenTitle",
    preOpenDescription: "status.preOpenDescription",
    openingDatetime: "status.openingDatetime",
    eligibility: "status.eligibility",
    contactInfo: "status.contactInfo",
  },
  greenhouse: {
    title: "greenhouse.title",
    totalBoxes: "greenhouse.totalBoxes",
    available: "greenhouse.available",
    occupied: "greenhouse.occupied",
    reserved: "greenhouse.reserved",
  },
  map: {
    viewMap: "map.viewMap",
    back: "map.back",
    legend: "map.legend",
    stateAvailable: "map.state.available",
    stateOccupied: "map.state.occupied",
    stateReserved: "map.state.reserved",
  },
  registration: {
    formTitle: "registration.formTitle",
    nameLabel: "registration.nameLabel",
    emailLabel: "registration.emailLabel",
    streetLabel: "registration.streetLabel",
    houseNumberLabel: "registration.houseNumberLabel",
    floorLabel: "registration.floorLabel",
    doorLabel: "registration.doorLabel",
    boxLabel: "registration.boxLabel",
    switchWarning: "registration.switchWarning",
    switchConfirm: "registration.switchConfirm",
    success: "registration.success",
    unregisterInfo: "registration.unregisterInfo",
  },
  address: {
    searchPlaceholder: "address.searchPlaceholder",
    searchHint: "address.searchHint",
    noResults: "address.noResults",
    selectedAddress: "address.selectedAddress",
    changeAddress: "address.changeAddress",
    ineligible: "address.ineligible",
    floorDoorHint: "address.floorDoorHint",
  },
  waitlist: {
    title: "waitlist.title",
    joinButton: "waitlist.joinButton",
    positionLabel: "waitlist.positionLabel",
    alreadyOnWaitlist: "waitlist.alreadyOnWaitlist",
    success: "waitlist.success",
    otherAvailable: "waitlist.otherAvailable",
    goToOther: "waitlist.goToOther",
  },
  validation: {
    emailRequired: "validation.emailRequired",
    emailInvalid: "validation.emailInvalid",
    nameRequired: "validation.nameRequired",
    streetInvalid: "validation.streetInvalid",
    houseNumberInvalid: "validation.houseNumberInvalid",
    floorDoorRequired: "validation.floorDoorRequired",
    boxIdInvalid: "validation.boxIdInvalid",
  },
  consent: {
    title: "consent.title",
    dataCollected: "consent.dataCollected",
    purpose: "consent.purpose",
    retention: "consent.retention",
    contact: "consent.contact",
    acknowledgment: "consent.acknowledgment",
    required: "consent.required",
  },
  policy: {
    oneApartmentRule: "policy.oneApartmentRule",
    noSelfUnregister: "policy.noSelfUnregister",
  },
  email: {
    confirmationSubject: "email.confirmationSubject",
    switchNote: "email.switchNote",
    careGuidelines: "email.careGuidelines",
  },
  about: {
    title: "about.title",
    description: "about.description",
    contact: "about.contact",
    sharedAbout: "about.sharedAbout",
    sharedPrivacy: "about.sharedPrivacy",
    sharedTerms: "about.sharedTerms",
  },
  admin: {
    link: "admin.link",
    login: "admin.login",
    email: "admin.email",
    password: "admin.password",
    loginFailed: "admin.loginFailed",
    backToPublic: "admin.backToPublic",
    openingTimeTitle: "admin.openingTimeTitle",
    openingTimeDescription: "admin.openingTimeDescription",
    currentValue: "admin.currentValue",
    lastUpdated: "admin.lastUpdated",
    newOpeningTime: "admin.newOpeningTime",
    save: "admin.save",
    settingsSaved: "admin.settingsSaved",
    tabRegistrations: "admin.tab.registrations",
    tabWaitlist: "admin.tab.waitlist",
    tabBoxes: "admin.tab.boxes",
    tabSettings: "admin.tab.settings",
    tabAudit: "admin.tab.audit",
    registrationsTitle: "admin.registrations.title",
    registrationsName: "admin.registrations.name",
    registrationsEmail: "admin.registrations.email",
    registrationsBox: "admin.registrations.box",
    registrationsApartment: "admin.registrations.apartment",
    registrationsStatus: "admin.registrations.status",
    registrationsDate: "admin.registrations.date",
    registrationsActions: "admin.registrations.actions",
    registrationsRemove: "admin.registrations.remove",
    registrationsNoRegistrations: "admin.registrations.noRegistrations",
    registrationsConfirmRemove: "admin.registrations.confirmRemove",
    registrationsRemoved: "admin.registrations.removed",
    waitlistTitle: "admin.waitlist.title",
    waitlistName: "admin.waitlist.name",
    waitlistEmail: "admin.waitlist.email",
    waitlistApartment: "admin.waitlist.apartment",
    waitlistStatus: "admin.waitlist.status",
    waitlistDate: "admin.waitlist.date",
    waitlistActions: "admin.waitlist.actions",
    waitlistAssign: "admin.waitlist.assign",
    waitlistNoEntries: "admin.waitlist.noEntries",
    waitlistAssigned: "admin.waitlist.assigned",
    waitlistAssignBoxId: "admin.waitlist.assignBoxId",
    waitlistConfirmAssign: "admin.waitlist.confirmAssign",
    boxesTitle: "admin.boxes.title",
    boxesGreenhouse: "admin.boxes.greenhouse",
    boxesName: "admin.boxes.name",
    boxesState: "admin.boxes.state",
    registrationsSelectBox: "admin.registrations.selectBox",
  },
} as const;

export type I18nKey = {
  [Domain in keyof typeof I18N_KEYS]: (typeof I18N_KEYS)[Domain][keyof (typeof I18N_KEYS)[Domain]];
}[keyof typeof I18N_KEYS];

/**
 * Default display labels for languages.
 * Used in the language selector UI.
 */
export const LANGUAGE_LABELS: Record<Language, string> = {
  da: "Dansk",
  en: "English",
};
