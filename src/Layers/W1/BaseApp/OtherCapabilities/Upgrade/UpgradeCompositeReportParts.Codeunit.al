// ------------------------------------------------------------------------------------------------
// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See License.txt in the project root for license information.
// ------------------------------------------------------------------------------------------------
namespace Microsoft.Upgrade;

using Microsoft.Foundation.Reporting;
using System.Environment.Configuration;
using System.Upgrade;

/// <summary>
/// Upgrade code to seed shipped Composite Report Layout themes and header/footer parts.
/// Seeds during database upgrade and on company open for new tenants provisioned from a
/// pre-built database image where BaseApp is installed but OnInstallAppPerDatabase may not have run.
/// </summary>
codeunit 104067 "Upgrade Composite Report Parts"
{
    Subtype = Upgrade;
    Access = Internal;
    // The OnAfterInitialization subscriber runs for every user at company open, so this codeunit must be executable
    // without a permission set or entitlement carrying it - hence inherent Execute here. The tabledata grant for the
    // write itself lives on "Composite Report Parts Mgt.", the codeunit that actually performs it, since elevation
    // applies to the object executing the operation and not to its callers.
    InherentEntitlements = X;
    InherentPermissions = X;

    trigger OnUpgradePerDatabase()
    begin
        RunUpgrade();
    end;

    trigger OnRun()
    begin
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"System Initialization", 'OnAfterInitialization', '', false, false)]
    local procedure OnCompanyOpen()
    begin
        SeedShippedParts();
    end;

    internal procedure RunUpgrade()
    begin
        SeedShippedParts();
    end;

    internal procedure SeedShippedParts()
    var
        CompositeReportPartsMgt: Codeunit "Composite Report Parts Mgt.";
        UpgradeTag: Codeunit "Upgrade Tag";
        UpgradeTagDefinitions: Codeunit "Upgrade Tag Definitions";
    begin
        // Cheap persisted guard shared by every entry point (install, upgrade and company open): a database that has
        // been fully seeded carries the upgrade tag and exits on this single read, keeping the seeding exactly-once.
        if UpgradeTag.HasDatabaseUpgradeTag(UpgradeTagDefinitions.GetCompositeReportPartsUpgradeTag()) then
            exit;

        // The tag is recorded only when every part was seeded. A part whose resource could not be read is a broken
        // package; leaving the tag off keeps the retry path open, so the next upgrade or company open on a fixed
        // package seeds it. Until then the pass reruns on each company open - the parts that did seed are upserted in
        // place, so the rerun is idempotent, and the cost is bounded to a build defect CI is meant to catch first.
        if CompositeReportPartsMgt.SeedDefaultParts() then
            UpgradeTag.SetDatabaseUpgradeTag(UpgradeTagDefinitions.GetCompositeReportPartsUpgradeTag());
    end;
}
