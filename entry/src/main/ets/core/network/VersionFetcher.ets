/**
 * Version fetcher for HMCL-HarmonyOS
 * Fetches version manifest and version JSON from Mojang / BMCLAPI
 */
import { HttpClient } from './HttpClient';
import { Constants } from '../../config/Constants';
import { VersionManifest, VersionInfo, GameVersionJson } from '../../model/GameVersion';

export class VersionFetcher {
  private apiBase: string;

  constructor(source: 'mojang' | 'bmclapi' = 'bmclapi') {
    this.apiBase = source === 'mojang'
      ? Constants.MOJANG_VERSION_MANIFEST
      : Constants.BMCLAPI_VERSION_MANIFEST;
  }

  /**
   * Fetch the full version manifest
   * Uses BMCLAPI as primary, Mojang as fallback
   */
  async fetchVersionManifest(): Promise<VersionManifest> {
    let result = await HttpClient.getJson<VersionManifest>(Constants.BMCLAPI_VERSION_MANIFEST);
    if (!result.success || !result.data) {
      result = await HttpClient.getJson<VersionManifest>(Constants.MOJANG_VERSION_MANIFEST);
    }
    if (!result.success || !result.data) {
      throw new Error('Failed to fetch version manifest');
    }
    return result.data;
  }

  /**
   * Fetch the version JSON for a specific version URL
   */
  async fetchVersionJson(versionUrl: string): Promise<GameVersionJson> {
    const result = await HttpClient.getJson<GameVersionJson>(versionUrl);
    if (!result.success || !result.data) {
      throw new Error(`Failed to fetch version JSON: ${versionUrl}`);
    }
    return result.data;
  }

  /**
   * Resolve the download URL for a library, with BMCLAPI mirror fallback
   */
  getLibraryDownloadUrl(library: any): string | null {
    if (library.downloads?.artifact?.url) {
      return library.downloads.artifact.url;
    }
    // Try BMCLAPI mirror path
    if (library.name) {
      const mavenPath = library.name.replace(/:/g, '/').replace(/\./g, '/');
      return `${Constants.BMCLAPI_LIBRARIES_BASE}${mavenPath}`;
    }
    return null;
  }

  /**
   * Filter versions from the manifest by type (release, snapshot, etc.)
   */
  filterVersions(manifest: VersionManifest, type?: string): VersionInfo[] {
    let versions = manifest.versions;
    if (type) {
      versions = versions.filter(v => v.type === type);
    }
    return versions;
  }
}