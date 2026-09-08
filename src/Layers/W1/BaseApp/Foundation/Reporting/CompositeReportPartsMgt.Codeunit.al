// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Foundation.Reporting;

using System.Environment.Configuration;
using System.Reflection;
using System.Utilities;

/// <summary>
/// Seeds the shipped Composite Layout theme and header/footer parts under Tenant Report Defaults on install and
/// upgrade, stored under this app's own App ID. Every part is a resource of this app, so one whose layout file
/// cannot be read is a build defect - SeedPart raises for it, but SeedDefaultParts logs it and keeps seeding the
/// rest rather than failing the whole pass on one bad part.
/// </summary>
codeunit 9667 "Composite Report Parts Mgt."
{
    Access = Internal;
    // Seeding runs from the OnAfterInitialization subscriber at company open for every user, so the write must
    // succeed regardless of the triggering user's own permissions or license entitlement - the same triple the
    // platform's own "Upgrade Tag" codeunit carries for its company-open-time write.
    InherentEntitlements = X;
    InherentPermissions = X;
    Permissions = tabledata "Tenant Report Layout" = rim;

    // Seeding is gated by a one-time upgrade tag (see "Upgrade Composite Report Parts"), so this only ever runs
    // once per database. Retiring a part here (removing its SeedPart call) leaves its row, and any
    // Report Layout List / Tenant Report Layout Cfg assignment referencing it, permanently orphaned on any
    // database that already seeded under an earlier version - this pass will never run again to clean it up.
    // If a part is retired, add a dedicated upgrade step with its own new upgrade tag that flips that row's
    // Layout Status to Retired and clears its assignments - Retired is a real lifecycle status the platform
    // already supports on this field, so there is no need to delete the row.
    //
    // Each part is seeded through SeedPartOrLogFailure, not SeedPart directly: this runs from the per-database
    // upgrade trigger and from company open for every user, so one part with a bad resource must not fail the
    // whole upgrade tag (and whatever else shares its upgrade phase) or block company open for every other
    // tenant. A failure is logged to telemetry instead, and the remaining parts still get seeded.
    internal procedure SeedDefaultParts()
    begin
        SeedPartOrLogFailure(ExternalDefaultTxt, 'ReportParts/HeaderFooterDesign/ExternalDefault.docx', Enum::"Report Layout Subtype"::HeaderFooter, ExternalDefaultDescTxt);
        SeedPartOrLogFailure(ExternalDefaultDetailedTxt, 'ReportParts/HeaderFooterDesign/ExternalDefaultDetailed.docx', Enum::"Report Layout Subtype"::HeaderFooter, ExternalDefaultDetailedDescTxt);
        SeedPartOrLogFailure(ExternalMinimalisticTxt, 'ReportParts/HeaderFooterDesign/ExternalMinimalistic.docx', Enum::"Report Layout Subtype"::HeaderFooter, ExternalMinimalisticDescTxt);
        SeedPartOrLogFailure(ExternalMinimalisticDetailedTxt, 'ReportParts/HeaderFooterDesign/ExternalMinimalisticDetailed.docx', Enum::"Report Layout Subtype"::HeaderFooter, ExternalMinimalisticDetailedDescTxt);
        SeedPartOrLogFailure(ExternalModernTxt, 'ReportParts/HeaderFooterDesign/ExternalModern.docx', Enum::"Report Layout Subtype"::HeaderFooter, ExternalModernDescTxt);
        SeedPartOrLogFailure(ExternalModernLogoTxt, 'ReportParts/HeaderFooterDesign/ExternalModernLogo.docx', Enum::"Report Layout Subtype"::HeaderFooter, ExternalModernLogoDescTxt);

        SeedPartOrLogFailure(InternalDefaultTxt, 'ReportParts/HeaderFooterDesign/InternalDefault.docx', Enum::"Report Layout Subtype"::HeaderFooter, InternalDefaultDescTxt);
        SeedPartOrLogFailure(InternalMinimalisticCenteredTxt, 'ReportParts/HeaderFooterDesign/InternalMinimalisticCentered.docx', Enum::"Report Layout Subtype"::HeaderFooter, InternalMinimalisticCenteredDescTxt);
        SeedPartOrLogFailure(InternalMinimalisticTxt, 'ReportParts/HeaderFooterDesign/InternalMinimalistic.docx', Enum::"Report Layout Subtype"::HeaderFooter, InternalMinimalisticDescTxt);
        SeedPartOrLogFailure(InternalModernTxt, 'ReportParts/HeaderFooterDesign/InternalModern.docx', Enum::"Report Layout Subtype"::HeaderFooter, InternalModernDescTxt);
        SeedPartOrLogFailure(InternalModernMaxiTxt, 'ReportParts/HeaderFooterDesign/InternalModernMaxi.docx', Enum::"Report Layout Subtype"::HeaderFooter, InternalModernMaxiDescTxt);

        SeedPartOrLogFailure(DefaultThemeTxt, 'ReportParts/ReportTheme/Default.dotx', Enum::"Report Layout Subtype"::Theme, DefaultThemeDescTxt);
        SeedPartOrLogFailure(CalmThemeTxt, 'ReportParts/ReportTheme/Calm.dotx', Enum::"Report Layout Subtype"::Theme, CalmThemeDescTxt);
        SeedPartOrLogFailure(PlayfulThemeTxt, 'ReportParts/ReportTheme/Playful.dotx', Enum::"Report Layout Subtype"::Theme, PlayfulThemeDescTxt);
    end;

    internal procedure SeedPartOrLogFailure(PartName: Text[250]; ResourceFile: Text; Subtype: Enum "Report Layout Subtype"; Description: Text)
    var
        PartLayout: Codeunit "Temp Blob";
        Dimensions: Dictionary of [Text, Text];
    begin
        // Only reading the resource is guarded by a try function; the database write is not. A try function call
        // may not write to the database on-premises (DisableWriteInsideTryFunctions defaults to true), and this runs
        // at company open and in the per-database upgrade - wrapping the write too failed company open on every fresh
        // database. A write that fails is a platform or tenant condition rather than a bad part, and is left to raise.
        if TryReadPartLayout(PartName, ResourceFile, PartLayout) then begin
            WritePart(PartName, PartLayout, Subtype, Description);
            exit;
        end;

        // The message stays static: Session.LogMessage ships it verbatim regardless of DataClassification, and
        // GetLastErrorText can carry customer content. Everything variable goes into the dimensions instead.
        // The error text is read with ExcludeCustomerContent set, so that what lands in the dimensions stays
        // within the SystemMetadata classification this event is logged under - the failing part is one of our
        // own resources, so the part name and resource file are all the diagnosis needs anyway.
        Dimensions.Add('PartName', PartName);
        Dimensions.Add('ResourceFile', ResourceFile);
        Dimensions.Add('ErrorText', GetLastErrorText(true));
        Session.LogMessage('0000CR1', SeedPartFailedTelemetryTxt, Verbosity::Error,
            DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, Dimensions);
    end;

    /// <summary>
    /// Seeds or overwrites a single shipped part. Raises if the part's own layout file is missing or unreadable -
    /// a build defect that can only happen in a broken package - rather than skipping it silently. Called directly
    /// like this, the error is the caller's to handle; SeedDefaultParts goes through SeedPartOrLogFailure instead
    /// so that one bad part cannot fail the whole seeding pass.
    /// </summary>
    internal procedure SeedPart(PartName: Text[250]; ResourceFile: Text; Subtype: Enum "Report Layout Subtype"; Description: Text)
    var
        PartLayout: Codeunit "Temp Blob";
    begin
        ReadPartLayout(PartName, ResourceFile, PartLayout);
        WritePart(PartName, PartLayout, Subtype, Description);
    end;

    [TryFunction]
    local procedure TryReadPartLayout(PartName: Text[250]; ResourceFile: Text; var PartLayout: Codeunit "Temp Blob")
    begin
        ReadPartLayout(PartName, ResourceFile, PartLayout);
    end;

    // Read-only by design: this is what runs inside TryReadPartLayout, so it must not touch the database.
    local procedure ReadPartLayout(PartName: Text[250]; ResourceFile: Text; var PartLayout: Codeunit "Temp Blob")
    begin
        ClearLastError();

        if not NavApp.ListResources(ResourceFile).Contains(ResourceFile) then
            Error(PartResourceError(PartName, ResourceFile, StrSubstNo(ResourceMissingDetailTxt, ResourceFile)));

        if not TryGetPartLayout(ResourceFile, PartLayout) then
            Error(PartResourceError(PartName, ResourceFile, StrSubstNo(ResourceNotReadableDetailTxt, ResourceFile, GetLastErrorText(true))));
    end;

    local procedure WritePart(PartName: Text[250]; var PartLayout: Codeunit "Temp Blob"; Subtype: Enum "Report Layout Subtype"; Description: Text)
    var
        TenantReportLayout: Record "Tenant Report Layout";
        CompositeLayoutLookupHelper: Codeunit "Composite Layout Lookup Helper";
        LayoutInStream: InStream;
        PartExists: Boolean;
    begin
        // Upsert rather than delete-then-insert: a retry after a partial failure (some parts already seeded before
        // an earlier Error()) overwrites those rows in place instead of needing to clear them first.
        PartExists := TenantReportLayout.Get(CompositeLayoutLookupHelper.GetTenantReportDefaultsReportID(), PartName, GetShippedPartAppId());
        if not PartExists then begin
            TenantReportLayout.Init();
            TenantReportLayout."Report ID" := CompositeLayoutLookupHelper.GetTenantReportDefaultsReportID();
            TenantReportLayout.Name := PartName;
            TenantReportLayout."App ID" := GetShippedPartAppId();
            TenantReportLayout."Company Name" := '';
        end;
        TenantReportLayout."Layout Format" := TenantReportLayout."Layout Format"::Word;
        TenantReportLayout."Layout Subtype" := Subtype;
        TenantReportLayout.Description := CopyStr(Description, 1, MaxStrLen(TenantReportLayout.Description));
        TenantReportLayout."Layout Status" := TenantReportLayout."Layout Status"::Approved;
        TenantReportLayout."MIME Type" := PartMimeType(Subtype);
        PartLayout.CreateInStream(LayoutInStream);
        TenantReportLayout.Layout.ImportStream(LayoutInStream, PartName);
        if PartExists then
            TenantReportLayout.Modify(true)
        else
            TenantReportLayout.Insert(true);
    end;

    [TryFunction]
    local procedure TryGetPartLayout(ResourceFile: Text; var PartLayout: Codeunit "Temp Blob")
    var
        ResourceInStream: InStream;
        PartLayoutOutStream: OutStream;
    begin
        NavApp.GetResource(ResourceFile, ResourceInStream);

        PartLayout.CreateOutStream(PartLayoutOutStream);
        CopyStream(PartLayoutOutStream, ResourceInStream);
    end;

    local procedure PartResourceError(PartName: Text; ResourceFile: Text; Detail: Text) LayoutErrorInfo: ErrorInfo
    var
        Dimensions: Dictionary of [Text, Text];
    begin
        LayoutErrorInfo.ErrorType := LayoutErrorInfo.ErrorType::Internal;
        LayoutErrorInfo.Verbosity := LayoutErrorInfo.Verbosity::Error;
        LayoutErrorInfo.DataClassification := LayoutErrorInfo.DataClassification::SystemMetadata;
        LayoutErrorInfo.Message := StrSubstNo(ResourceNotReadableErr, PartName);
        LayoutErrorInfo.DetailedMessage := Detail;

        Dimensions.Add('PartName', PartName);
        Dimensions.Add('ResourceFile', ResourceFile);
        LayoutErrorInfo.CustomDimensions := Dimensions;
    end;

    internal procedure GetShippedPartAppId() AppId: Guid
    var
        CurrentModuleInfo: ModuleInfo;
    begin
        NavApp.GetCurrentModuleInfo(CurrentModuleInfo);
        AppId := CurrentModuleInfo.Id;
    end;

    local procedure PartMimeType(Subtype: Enum "Report Layout Subtype"): Text[255]
    begin
        if Subtype = Subtype::Theme then
            exit(ThemeMimeTypeTxt);

        exit(HeaderFooterMimeTypeTxt);
    end;

    var
        ExternalDefaultTxt: Label 'External Default', Locked = true;
        ExternalDefaultDetailedTxt: Label 'External Default Detailed', Locked = true;
        ExternalMinimalisticTxt: Label 'External Minimalistic', Locked = true;
        ExternalMinimalisticDetailedTxt: Label 'External Minimalistic Detailed', Locked = true;
        ExternalModernTxt: Label 'External Modern', Locked = true;
        ExternalModernLogoTxt: Label 'External Modern Logo', Locked = true;
        InternalDefaultTxt: Label 'Internal Default', Locked = true;
        InternalMinimalisticCenteredTxt: Label 'Internal Minimalistic Centered', Locked = true;
        InternalMinimalisticTxt: Label 'Internal Minimalistic', Locked = true;
        InternalModernTxt: Label 'Internal Modern', Locked = true;
        InternalModernMaxiTxt: Label 'Internal Modern Maxi', Locked = true;
        DefaultThemeTxt: Label 'Default', Locked = true;
        CalmThemeTxt: Label 'Calm', Locked = true;
        PlayfulThemeTxt: Label 'Playful', Locked = true;
        ExternalDefaultDescTxt: Label 'Header/footer design for portrait or landscape. Header with company logo, report name, document date and page number; footer with homepage, phone, email and fax number. Standard external layout for customer-facing documents.';
        ExternalDefaultDetailedDescTxt: Label 'Header/footer design for portrait or landscape. Header with company logo, report name, document date and page number; footer with homepage, phone, email, fax plus bank, bank account, VAT reg. no. and giro no. Detailed external layout.';
        ExternalMinimalisticDescTxt: Label 'Header/footer design for portrait or landscape, minimalistic. Header with company logo and report name only; footer with page number, company name, homepage, phone, email and fax. A clean, light external layout.';
        ExternalMinimalisticDetailedDescTxt: Label 'Header/footer design for portrait or landscape, minimalistic. Header with company logo and report name; footer with page number, company name, homepage, phone, email, fax plus bank, bank account, VAT reg. no. and giro no.';
        ExternalModernDescTxt: Label 'Header/footer design for portrait or landscape, modern style without logo. Header with report name, document date and company name in uppercase; footer with page number and full contact details (homepage, phone, email, fax, VAT, giro, bank).';
        ExternalModernLogoDescTxt: Label 'Header/footer design for portrait or landscape. Header with company logo, report name, document date and page number; footer with homepage, phone, email, fax plus bank, bank account, VAT reg. no. and giro no. Modern external layout.';
        InternalDefaultDescTxt: Label 'Header/footer design for portrait or landscape, for internal documents. Header with company logo, report name and document date; footer with page number.';
        InternalMinimalisticCenteredDescTxt: Label 'Header/footer design for portrait or landscape, minimalist and centred, for internal documents. Header with centred logo, report name and document date; footer with page number.';
        InternalMinimalisticDescTxt: Label 'Header/footer design for portrait or landscape, minimalistic, for internal documents. Header with report name and document date; footer with page number.';
        InternalModernDescTxt: Label 'Header/footer design for portrait or landscape, modern style, for internal documents. Header with company logo, report name and document date; footer with page number.';
        InternalModernMaxiDescTxt: Label 'Header/footer design for portrait or landscape, modern style with a large header, for internal documents. Header with company logo, report name and document date; footer with page number.';
        DefaultThemeDescTxt: Label 'Simple and clear, so the details that matter stand out. Styling-only theme: neutral Segoe UI in semibold and regular for hierarchy, dark-grey text on white, calm accent colours, and softly banded table rows. Works for most reports out of the box.';
        CalmThemeDescTxt: Label 'Classic and calm, and easy to read. Styling-only theme: Sitka serif in semibold and regular for hierarchy, with dark-green text on a soft beige background. A timeless look that gives your reports a quieter, more classic feel.';
        PlayfulThemeDescTxt: Label 'Dynamic and lively, a fresh take on a professional report. Styling-only theme: geometric Bahnschrift in semibold and regular for hierarchy, with backgrounds alternating between green and pink for an energetic, modern feel.';
        ResourceNotReadableErr: Label 'The layout file for the report part %1 could not be read. The part was not seeded.', Comment = '%1 = the name of the shipped theme or header/footer part';
        ResourceNotReadableDetailTxt: Label 'Resource: %1. Platform error: %2', Locked = true;
        ResourceMissingDetailTxt: Label 'Resource: %1. The app does not carry this resource.', Locked = true;
        SeedPartFailedTelemetryTxt: Label 'Failed to seed a shipped Composite Report Part.', Locked = true;
        ThemeMimeTypeTxt: Label 'reportlayout/dotx', Locked = true;
        HeaderFooterMimeTypeTxt: Label 'reportlayout/docx', Locked = true;
}
