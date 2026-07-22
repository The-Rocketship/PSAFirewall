<#
.SYNOPSIS
    PSAFirewall - Modern Dark Minimalist PowerShell GUI for Windows Defender Firewall with Advanced Security.
.DESCRIPTION
    Provides complete management of Windows NetFirewall rules and profiles:
    - View, Search, Filter, Sort Inbound & Outbound rules with high-performance DataGrid virtualization.
    - Create, Edit, Enable/Disable, and Delete firewall rules.
    - Manage Domain, Private, and Public profile settings and default actions.
    - Import and Export firewall policy backups.
.NOTES
    Requires Administrator Privileges.
#>

# --- 1. ELEVATION & ASSEMBLY INITIALIZATION ---
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
if (-not $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $CommandLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Start-Process powershell.exe -Verb RunAs -ArgumentList $CommandLine
        exit
    } catch {
        [System.Windows.Forms.MessageBox]::Show("PSAFirewall requires Administrator privileges to manage Windows Firewall rules.", "Elevation Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit
    }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms
Import-Module NetSecurity -ErrorAction SilentlyContinue

# --- 2. DYNAMIC ICON ENGINE ---
function Get-AppIcon {
    try {
        $Bmp = New-Object System.Drawing.Bitmap(64, 64)
        $G = [System.Drawing.Graphics]::FromImage($Bmp)
        $G.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $G.Clear([System.Drawing.Color]::Transparent)

        # Draw Dark Blue Shield
        $ShieldBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 30, 58, 138))
        $BorderPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 96, 165, 250), 3)

        $Points = @(
            New-Object System.Drawing.Point(32, 4),
            New-Object System.Drawing.Point(58, 14),
            New-Object System.Drawing.Point(58, 36),
            New-Object System.Drawing.Point(32, 60),
            New-Object System.Drawing.Point(6, 36),
            New-Object System.Drawing.Point(6, 14)
        )
        $G.FillPolygon($ShieldBrush, $Points)
        $G.DrawPolygon($BorderPen, $Points)

        # Draw "FW" text
        $Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
        $TextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 244, 244, 245))
        $SF = New-Object System.Drawing.StringFormat
        $SF.Alignment = [System.Drawing.StringAlignment]::Center
        $SF.LineAlignment = [System.Drawing.StringAlignment]::Center
        $G.DrawString("FW", $Font, $TextBrush, 32, 33, $SF)

        # Convert to PNG MemoryStream & WPF BitmapImage
        $MS = New-Object System.IO.MemoryStream
        $Bmp.Save($MS, [System.Drawing.Imaging.ImageFormat]::Png)
        $MS.Position = 0

        $BitmapImage = New-Object System.Windows.Media.Imaging.BitmapImage
        $BitmapImage.BeginInit()
        $BitmapImage.StreamSource = $MS
        $BitmapImage.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $BitmapImage.EndInit()
        $BitmapImage.Freeze()

        $G.Dispose()
        $Bmp.Dispose()
        return $BitmapImage
    } catch {
        return $null
    }
}

$Script:AppIcon = Get-AppIcon

# --- 3. REUSABLE DARK XAML STYLES (DRY DESIGN SYSTEM) ---
$SharedStylesXaml = @"
        <SolidColorBrush x:Key="BgDark" Color="#121214"/>
        <SolidColorBrush x:Key="CardDark" Color="#1E1E22"/>
        <SolidColorBrush x:Key="HeaderDark" Color="#18181B"/>
        <SolidColorBrush x:Key="BorderDark" Color="#27272A"/>
        <SolidColorBrush x:Key="AccentBlue" Color="#3B82F6"/>
        <SolidColorBrush x:Key="TextMain" Color="#F4F4F5"/>
        <SolidColorBrush x:Key="TextMuted" Color="#A1A1AA"/>

        <!-- Custom ScrollBar -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="#121214"/>
            <Setter Property="Foreground" Value="#3F3F46"/>
            <Setter Property="Width" Value="8"/>
        </Style>

        <!-- Base Button Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#25252B"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="Margin" Value="2"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" 
                                BorderBrush="{TemplateBinding BorderBrush}" 
                                BorderThickness="{TemplateBinding BorderThickness}" 
                                CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#32323D"/>
                                <Setter TargetName="border" Property="BorderBrush" Value="#52525B"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1D1D22"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#3B82F6"/>
            <Setter Property="Foreground" Value="#FFFFFF"/>
            <Setter Property="BorderBrush" Value="#60A5FA"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#2563EB"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#1D4ED8"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
            <Setter Property="Background" Value="#991B1B"/>
            <Setter Property="Foreground" Value="#FEE2E2"/>
            <Setter Property="BorderBrush" Value="#DC2626"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="5" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#B91C1C"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#7F1D1D"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Custom TextBox -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#18181C"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="CaretBrush" Value="#F4F4F5"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                            <ScrollViewer x:Name="PART_ContentHost"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="#3B82F6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Custom Dark ComboBox -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#25252B"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="SnapsToDevicePixels" Value="True"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBox">
                        <Grid>
                            <ToggleButton x:Name="ToggleButton" Focusable="false" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" ClickMode="Press" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                                <ToggleButton.Template>
                                    <ControlTemplate TargetType="ToggleButton">
                                        <Border x:Name="Border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="20"/>
                                                </Grid.ColumnDefinitions>
                                                <Path x:Name="Arrow" Grid.Column="1" Fill="#A1A1AA" HorizontalAlignment="Center" VerticalAlignment="Center" Data="M 0 0 L 4 4 L 8 0 Z"/>
                                            </Grid>
                                        </Border>
                                        <ControlTemplate.Triggers>
                                            <Trigger Property="IsMouseOver" Value="True">
                                                <Setter TargetName="Border" Property="Background" Value="#32323D"/>
                                                <Setter TargetName="Arrow" Property="Fill" Value="#F4F4F5"/>
                                            </Trigger>
                                        </ControlTemplate.Triggers>
                                    </ControlTemplate>
                                </ToggleButton.Template>
                            </ToggleButton>
                            <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False" Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="10,6,26,6" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                            <Popup x:Name="Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                                <Grid x:Name="DropDown" SnapsToDevicePixels="True" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}">
                                    <Border x:Name="DropDownBorder" Background="#18181C" BorderBrush="#3F3F46" BorderThickness="1" CornerRadius="4" Margin="0,2,0,0">
                                        <ScrollViewer Margin="2" SnapsToDevicePixels="True">
                                            <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained" />
                                        </ScrollViewer>
                                    </Border>
                                </Grid>
                            </Popup>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBoxItem">
            <Setter Property="Background" Value="#18181C"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="Padding" Value="8,6"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ComboBoxItem">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#32323D"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="#3B82F6"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="4"/>
        </Style>

        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Margin" Value="4"/>
        </Style>

        <!-- Custom TabControl & TabItem -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="#18181C"/>
            <Setter Property="BorderBrush" Value="#27272A"/>
        </Style>

        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#1E1E23"/>
            <Setter Property="Foreground" Value="#A1A1AA"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Border" Background="{TemplateBinding Background}" BorderBrush="#27272A" BorderThickness="1,1,1,0" CornerRadius="4,4,0,0" Padding="{TemplateBinding Padding}" Margin="0,0,4,0">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#25252B"/>
                                <Setter TargetName="Border" Property="BorderBrush" Value="#3B82F6"/>
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="#FFFFFF"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
"@

# --- 4. MAIN WINDOW XAML ---
[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PSA Firewall - Windows Advanced Security Manager" Height="780" Width="1240"
        MinHeight="650" MinWidth="1000" WindowStartupLocation="CenterScreen"
        Background="#121214" Foreground="#F4F4F5" FontFamily="Segoe UI, Segoe UI Variable, Arial">
    <Window.Resources>
        $SharedStylesXaml

        <!-- DataGrid Styles with High-Performance Virtualization -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="#18181C"/>
            <Setter Property="RowBackground" Value="#18181C"/>
            <Setter Property="AlternatingRowBackground" Value="#1E1E23"/>
            <Setter Property="Foreground" Value="#F4F4F5"/>
            <Setter Property="BorderBrush" Value="#27272A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#27272A"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="RowHeight" Value="34"/>
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="CanUserResizeRows" Value="False"/>
            <Setter Property="VirtualizingStackPanel.IsVirtualizing" Value="True"/>
            <Setter Property="VirtualizingStackPanel.VirtualizationMode" Value="Recycling"/>
            <Setter Property="EnableColumnVirtualization" Value="True"/>
        </Style>

        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#202026"/>
            <Setter Property="Foreground" Value="#A1A1AA"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="BorderBrush" Value="#27272A"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
        </Style>

        <Style TargetType="DataGridRow">
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2A2A33"/>
                </Trigger>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#323242"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Background="{TemplateBinding Background}" BorderThickness="0" Padding="{TemplateBinding Padding}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="64"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="30"/>
        </Grid.RowDefinitions>

        <!-- Top Header Bar -->
        <Border Grid.Row="0" Background="#18181B" BorderBrush="#27272A" BorderThickness="0,0,0,1">
            <Grid Margin="16,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Width="36" Height="36" CornerRadius="8" Background="#1E3A8A" Margin="0,0,12,0">
                        <TextBlock Text="FW" FontSize="15" FontWeight="Bold" Foreground="#60A5FA" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel VerticalAlignment="Center">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="PSA FIREWALL" FontSize="16" FontWeight="Bold" Foreground="#F4F4F5"/>
                            <Border Background="#065F46" Padding="6,2" CornerRadius="4" Margin="10,0,0,0" VerticalAlignment="Center">
                                <TextBlock Text="ADMINISTRATOR" FontSize="9" FontWeight="Bold" Foreground="#34D399"/>
                            </Border>
                        </StackPanel>
                        <TextBlock Text="Windows Defender Firewall with Advanced Security" FontSize="11" Foreground="#A1A1AA"/>
                    </StackPanel>
                </StackPanel>

                <!-- Profile Status Cards -->
                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
                    <Border Background="#1E1E23" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="10,5" Margin="4,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Domain:" FontSize="11" Foreground="#A1A1AA" Margin="0,0,6,0"/>
                            <TextBlock x:Name="TxtDomainStatus" Text="Active" FontSize="11" FontWeight="SemiBold" Foreground="#34D399"/>
                        </StackPanel>
                    </Border>

                    <Border Background="#1E1E23" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="10,5" Margin="4,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Private:" FontSize="11" Foreground="#A1A1AA" Margin="0,0,6,0"/>
                            <TextBlock x:Name="TxtPrivateStatus" Text="Active" FontSize="11" FontWeight="SemiBold" Foreground="#34D399"/>
                        </StackPanel>
                    </Border>

                    <Border Background="#1E1E23" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="10,5" Margin="4,0">
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="Public:" FontSize="11" Foreground="#A1A1AA" Margin="0,0,6,0"/>
                            <TextBlock x:Name="TxtPublicStatus" Text="Active" FontSize="11" FontWeight="SemiBold" Foreground="#34D399"/>
                        </StackPanel>
                    </Border>
                </StackPanel>

                <!-- Global Action Buttons -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="BtnManageProfiles" Content="Profiles" Padding="10,6" Margin="4,0"/>
                    <Button x:Name="BtnExportBackup" Content="Export Policy" Padding="10,6" Margin="4,0"/>
                    <Button x:Name="BtnImportBackup" Content="Import Policy" Padding="10,6" Margin="4,0"/>
                    <Button x:Name="BtnRefreshAll" Content="Refresh" Style="{StaticResource PrimaryButton}" Padding="12,6" Margin="4,0"/>
                </StackPanel>
            </Grid>
        </Border>

        <!-- Main Body Grid -->
        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="220"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Sidebar Navigation -->
            <Border Grid.Column="0" Background="#18181C" BorderBrush="#27272A" BorderThickness="0,0,1,0">
                <DockPanel LastChildFill="True" Margin="10,14">
                    <StackPanel DockPanel.Dock="Top">
                        <TextBlock Text="NAVIGATION" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="8,0,0,8"/>
                        <RadioButton x:Name="NavInbound" Content="Inbound Rules" GroupName="NavGroup" IsChecked="True" Style="{StaticResource {x:Type ToggleButton}}" Height="38" Margin="0,2" Padding="12,0" HorizontalContentAlignment="Left" Background="Transparent" Foreground="#F4F4F5" BorderThickness="0"/>
                        <RadioButton x:Name="NavOutbound" Content="Outbound Rules" GroupName="NavGroup" Style="{StaticResource {x:Type ToggleButton}}" Height="38" Margin="0,2" Padding="12,0" HorizontalContentAlignment="Left" Background="Transparent" Foreground="#F4F4F5" BorderThickness="0"/>
                        <RadioButton x:Name="NavProfiles" Content="Firewall Profiles" GroupName="NavGroup" Style="{StaticResource {x:Type ToggleButton}}" Height="38" Margin="0,2" Padding="12,0" HorizontalContentAlignment="Left" Background="Transparent" Foreground="#F4F4F5" BorderThickness="0"/>

                        <Separator Background="#27272A" Margin="0,14"/>

                        <TextBlock Text="FIREWALL QUICK ACTIONS" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="8,0,0,8"/>
                        <Button x:Name="BtnQuickDisableAll" Content="Disable All Profiles" Style="{StaticResource DangerButton}" HorizontalAlignment="Stretch" Margin="0,4"/>
                        <Button x:Name="BtnQuickRestoreDefaults" Content="Restore Firewall Defaults" HorizontalAlignment="Stretch" Margin="0,4"/>
                    </StackPanel>

                    <!-- Sidebar Stats -->
                    <Border DockPanel.Dock="Bottom" Background="#1E1E23" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="10">
                        <StackPanel>
                            <TextBlock Text="Rule Statistics" FontSize="11" FontWeight="Bold" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                            <Grid Margin="0,2">
                                <TextBlock Text="Total Inbound:" FontSize="11" Foreground="#71717A"/>
                                <TextBlock x:Name="TxtTotalInboundCount" Text="0" FontSize="11" FontWeight="Bold" HorizontalAlignment="Right" Foreground="#F4F4F5"/>
                            </Grid>
                            <Grid Margin="0,2">
                                <TextBlock Text="Total Outbound:" FontSize="11" Foreground="#71717A"/>
                                <TextBlock x:Name="TxtTotalOutboundCount" Text="0" FontSize="11" FontWeight="Bold" HorizontalAlignment="Right" Foreground="#F4F4F5"/>
                            </Grid>
                            <Grid Margin="0,2">
                                <TextBlock Text="Enabled Rules:" FontSize="11" Foreground="#71717A"/>
                                <TextBlock x:Name="TxtTotalEnabledCount" Text="0" FontSize="11" FontWeight="Bold" HorizontalAlignment="Right" Foreground="#34D399"/>
                            </Grid>
                        </StackPanel>
                    </Border>
                </DockPanel>
            </Border>

            <!-- Main Views Area -->
            <Grid Grid.Column="1" Margin="14">
                <!-- VIEW 1: RULES GRID -->
                <Grid x:Name="ViewRules" Visibility="Visible">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>

                    <!-- Filters Panel -->
                    <Border Grid.Row="0" Background="#18181C" BorderBrush="#27272A" BorderThickness="1" CornerRadius="6" Padding="12,10" Margin="0,0,0,10">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="130"/>
                                <ColumnDefinition Width="130"/>
                                <ColumnDefinition Width="130"/>
                                <ColumnDefinition Width="120"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0" Margin="0,0,10,0">
                                <TextBlock Text="SEARCH RULES" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="0,0,0,4"/>
                                <TextBox x:Name="TxtSearchQuery" ToolTip="Type rule name, program, group, or port..."/>
                            </StackPanel>

                            <StackPanel Grid.Column="1" Margin="0,0,8,0">
                                <TextBlock Text="ACTION" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="0,0,0,4"/>
                                <ComboBox x:Name="CmbFilterAction" SelectedIndex="0">
                                    <ComboBoxItem Content="All Actions"/>
                                    <ComboBoxItem Content="Allow Only"/>
                                    <ComboBoxItem Content="Block Only"/>
                                </ComboBox>
                            </StackPanel>

                            <StackPanel Grid.Column="2" Margin="0,0,8,0">
                                <TextBlock Text="STATUS" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="0,0,0,4"/>
                                <ComboBox x:Name="CmbFilterStatus" SelectedIndex="0">
                                    <ComboBoxItem Content="All Statuses"/>
                                    <ComboBoxItem Content="Enabled Only"/>
                                    <ComboBoxItem Content="Disabled Only"/>
                                </ComboBox>
                            </StackPanel>

                            <StackPanel Grid.Column="3" Margin="0,0,8,0">
                                <TextBlock Text="PROFILE" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="0,0,0,4"/>
                                <ComboBox x:Name="CmbFilterProfile" SelectedIndex="0">
                                    <ComboBoxItem Content="All Profiles"/>
                                    <ComboBoxItem Content="Domain"/>
                                    <ComboBoxItem Content="Private"/>
                                    <ComboBoxItem Content="Public"/>
                                    <ComboBoxItem Content="Any"/>
                                </ComboBox>
                            </StackPanel>

                            <StackPanel Grid.Column="4">
                                <TextBlock Text="PROTOCOL" FontSize="10" FontWeight="Bold" Foreground="#71717A" Margin="0,0,0,4"/>
                                <ComboBox x:Name="CmbFilterProtocol" SelectedIndex="0">
                                    <ComboBoxItem Content="All Protocols"/>
                                    <ComboBoxItem Content="TCP"/>
                                    <ComboBoxItem Content="UDP"/>
                                    <ComboBoxItem Content="ICMPv4"/>
                                    <ComboBoxItem Content="ICMPv6"/>
                                    <ComboBoxItem Content="Any"/>
                                </ComboBox>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <!-- Rule Action Toolbar -->
                    <DockPanel Grid.Row="1" Margin="0,0,0,10">
                        <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
                            <Button x:Name="BtnNewRule" Content="[+] New Rule" Style="{StaticResource PrimaryButton}" Padding="14,6" Margin="0,0,6,0"/>
                            <Button x:Name="BtnEditRule" Content="Edit Selected" Padding="12,6" Margin="0,0,6,0"/>
                            <Button x:Name="BtnToggleRule" Content="Toggle State" Padding="12,6" Margin="0,0,6,0"/>
                            <Button x:Name="BtnDeleteRule" Content="[x] Delete Rule" Style="{StaticResource DangerButton}" Padding="12,6" Margin="0,0,6,0"/>
                        </StackPanel>
                        <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" HorizontalAlignment="Right" VerticalAlignment="Center">
                            <TextBlock x:Name="TxtFilteredCount" Text="Showing 0 of 0 rules" FontSize="11" Foreground="#A1A1AA" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        </StackPanel>
                    </DockPanel>

                    <!-- Rules DataGrid -->
                    <Grid Grid.Row="2">
                        <DataGrid x:Name="GridRules">
                            <DataGrid.Columns>
                                <DataGridTemplateColumn Header="STATUS" Width="80">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="4" Padding="6,2" HorizontalAlignment="Center" VerticalAlignment="Center" Background="{Binding EnabledBg}">
                                                <TextBlock Text="{Binding EnabledText}" Foreground="{Binding EnabledFg}" FontSize="10" FontWeight="Bold"/>
                                            </Border>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>

                                <DataGridTemplateColumn Header="ACTION" Width="80">
                                    <DataGridTemplateColumn.CellTemplate>
                                        <DataTemplate>
                                            <Border CornerRadius="4" Padding="6,2" HorizontalAlignment="Center" VerticalAlignment="Center" Background="{Binding ActionBg}">
                                                <TextBlock Text="{Binding ActionText}" Foreground="{Binding ActionFg}" FontSize="10" FontWeight="Bold"/>
                                            </Border>
                                        </DataTemplate>
                                    </DataGridTemplateColumn.CellTemplate>
                                </DataGridTemplateColumn>

                                <DataGridTextColumn Header="NAME" Binding="{Binding DisplayName}" Width="220"/>
                                <DataGridTextColumn Header="GROUP" Binding="{Binding DisplayGroup}" Width="140"/>
                                <DataGridTextColumn Header="PROFILE" Binding="{Binding Profile}" Width="100"/>
                                <DataGridTextColumn Header="PROTOCOL" Binding="{Binding Protocol}" Width="80"/>
                                <DataGridTextColumn Header="LOCAL PORT" Binding="{Binding LocalPort}" Width="100"/>
                                <DataGridTextColumn Header="REMOTE PORT" Binding="{Binding RemotePort}" Width="100"/>
                                <DataGridTextColumn Header="PROGRAM / PATH" Binding="{Binding Program}" Width="*"/>
                            </DataGrid.Columns>
                        </DataGrid>

                        <Border x:Name="OverlayLoading" Background="#CC121214" Visibility="Collapsed">
                            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
                                <ProgressBar IsIndeterminate="True" Width="180" Height="6" Foreground="#3B82F6" Background="#27272A" BorderThickness="0" Margin="0,0,0,12"/>
                                <TextBlock x:Name="TxtLoadingMessage" Text="Querying Windows Firewall Rules..." FontSize="13" Foreground="#F4F4F5" HorizontalAlignment="Center"/>
                            </StackPanel>
                        </Border>
                    </Grid>
                </Grid>

                <!-- VIEW 2: FIREWALL PROFILES -->
                <Grid x:Name="ViewProfiles" Visibility="Collapsed">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel Margin="10">
                            <TextBlock Text="FIREWALL PROFILE SETTINGS" FontSize="18" FontWeight="Bold" Foreground="#F4F4F5" Margin="0,0,0,4"/>
                            <TextBlock Text="Configure global state, default connection behaviors, and logging for Domain, Private, and Public network profiles." FontSize="12" Foreground="#A1A1AA" Margin="0,0,0,16"/>

                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <!-- Domain Card -->
                                <Border Grid.Column="0" Background="#18181C" BorderBrush="#27272A" BorderThickness="1" CornerRadius="8" Padding="16" Margin="0,0,10,0">
                                    <StackPanel>
                                        <TextBlock Text="Domain Profile" FontSize="15" FontWeight="Bold" Foreground="#38BDF8" Margin="0,0,12,0"/>
                                        <CheckBox x:Name="ChkDomainEnabled" Content="Firewall Enabled" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,10"/>
                                        <TextBlock Text="Default Inbound Action" FontSize="11" Foreground="#A1A1AA" Margin="0,4,0,2"/>
                                        <ComboBox x:Name="CmbDomainInbound" Margin="0,0,0,10">
                                            <ComboBoxItem Content="Block"/>
                                            <ComboBoxItem Content="BlockAllInbound"/>
                                            <ComboBoxItem Content="Allow"/>
                                        </ComboBox>
                                        <TextBlock Text="Default Outbound Action" FontSize="11" Foreground="#A1A1AA" Margin="0,4,0,2"/>
                                        <ComboBox x:Name="CmbDomainOutbound" Margin="0,0,0,14">
                                            <ComboBoxItem Content="Allow"/>
                                            <ComboBoxItem Content="Block"/>
                                        </ComboBox>
                                        <Separator Background="#27272A" Margin="0,0,0,10"/>
                                        <Button x:Name="BtnSaveDomainProfile" Content="Save Domain Settings" Style="{StaticResource PrimaryButton}"/>
                                    </StackPanel>
                                </Border>

                                <!-- Private Card -->
                                <Border Grid.Column="1" Background="#18181C" BorderBrush="#27272A" BorderThickness="1" CornerRadius="8" Padding="16" Margin="5,0,5,0">
                                    <StackPanel>
                                        <TextBlock Text="Private Profile" FontSize="15" FontWeight="Bold" Foreground="#34D399" Margin="0,0,12,0"/>
                                        <CheckBox x:Name="ChkPrivateEnabled" Content="Firewall Enabled" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,10"/>
                                        <TextBlock Text="Default Inbound Action" FontSize="11" Foreground="#A1A1AA" Margin="0,4,0,2"/>
                                        <ComboBox x:Name="CmbPrivateInbound" Margin="0,0,0,10">
                                            <ComboBoxItem Content="Block"/>
                                            <ComboBoxItem Content="BlockAllInbound"/>
                                            <ComboBoxItem Content="Allow"/>
                                        </ComboBox>
                                        <TextBlock Text="Default Outbound Action" FontSize="11" Foreground="#A1A1AA" Margin="0,4,0,2"/>
                                        <ComboBox x:Name="CmbPrivateOutbound" Margin="0,0,0,14">
                                            <ComboBoxItem Content="Allow"/>
                                            <ComboBoxItem Content="Block"/>
                                        </ComboBox>
                                        <Separator Background="#27272A" Margin="0,0,0,10"/>
                                        <Button x:Name="BtnSavePrivateProfile" Content="Save Private Settings" Style="{StaticResource PrimaryButton}"/>
                                    </StackPanel>
                                </Border>

                                <!-- Public Card -->
                                <Border Grid.Column="2" Background="#18181C" BorderBrush="#27272A" BorderThickness="1" CornerRadius="8" Padding="16" Margin="10,0,0,0">
                                    <StackPanel>
                                        <TextBlock Text="Public Profile" FontSize="15" FontWeight="Bold" Foreground="#F43F5E" Margin="0,0,12,0"/>
                                        <CheckBox x:Name="ChkPublicEnabled" Content="Firewall Enabled" FontSize="12" FontWeight="SemiBold" Margin="0,4,0,10"/>
                                        <TextBlock Text="Default Inbound Action" FontSize="11" Foreground="#A1A1AA" Margin="0,4,0,2"/>
                                        <ComboBox x:Name="CmbPublicInbound" Margin="0,0,0,10">
                                            <ComboBoxItem Content="Block"/>
                                            <ComboBoxItem Content="BlockAllInbound"/>
                                            <ComboBoxItem Content="Allow"/>
                                        </ComboBox>
                                        <TextBlock Text="Default Outbound Action" FontSize="11" Foreground="#A1A1AA" Margin="0,4,0,2"/>
                                        <ComboBox x:Name="CmbPublicOutbound" Margin="0,0,0,14">
                                            <ComboBoxItem Content="Allow"/>
                                            <ComboBoxItem Content="Block"/>
                                        </ComboBox>
                                        <Separator Background="#27272A" Margin="0,0,0,10"/>
                                        <Button x:Name="BtnSavePublicProfile" Content="Save Public Settings" Style="{StaticResource PrimaryButton}"/>
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>
            </Grid>
        </Grid>

        <!-- Status Footer -->
        <Border Grid.Row="2" Background="#18181B" BorderBrush="#27272A" BorderThickness="0,1,0,0">
            <Grid Margin="12,0">
                <TextBlock x:Name="TxtStatusFooter" Text="Ready." FontSize="11" Foreground="#A1A1AA" VerticalAlignment="Center"/>
                <TextBlock Text="PSA Firewall v1.0 | NetSecurity PowerShell API" FontSize="11" Foreground="#52525B" HorizontalAlignment="Right" VerticalAlignment="Center"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

$Reader = (New-Object System.Xml.XmlNodeReader $Xaml)
$Window = [Windows.Markup.XamlReader]::Load($Reader)

if ($Script:AppIcon) {
    try { $Window.Icon = $Script:AppIcon } catch {}
}

# --- 5. BIND CONTROLS ---
$GridRules            = $Window.FindName("GridRules")
$OverlayLoading       = $Window.FindName("OverlayLoading")
$TxtLoadingMessage    = $Window.FindName("TxtLoadingMessage")
$TxtStatusFooter      = $Window.FindName("TxtStatusFooter")

$NavInbound           = $Window.FindName("NavInbound")
$NavOutbound          = $Window.FindName("NavOutbound")
$NavProfiles          = $Window.FindName("NavProfiles")

$ViewRules            = $Window.FindName("ViewRules")
$ViewProfiles         = $Window.FindName("ViewProfiles")

$TxtSearchQuery       = $Window.FindName("TxtSearchQuery")
$CmbFilterAction      = $Window.FindName("CmbFilterAction")
$CmbFilterStatus      = $Window.FindName("CmbFilterStatus")
$CmbFilterProfile     = $Window.FindName("CmbFilterProfile")
$CmbFilterProtocol    = $Window.FindName("CmbFilterProtocol")

$BtnNewRule           = $Window.FindName("BtnNewRule")
$BtnEditRule          = $Window.FindName("BtnEditRule")
$BtnToggleRule        = $Window.FindName("BtnToggleRule")
$BtnDeleteRule        = $Window.FindName("BtnDeleteRule")
$BtnRefreshAll        = $Window.FindName("BtnRefreshAll")

$BtnManageProfiles    = $Window.FindName("BtnManageProfiles")
$BtnExportBackup      = $Window.FindName("BtnExportBackup")
$BtnImportBackup      = $Window.FindName("BtnImportBackup")
$BtnQuickDisableAll   = $Window.FindName("BtnQuickDisableAll")
$BtnQuickRestoreDefaults = $Window.FindName("BtnQuickRestoreDefaults")

$TxtDomainStatus      = $Window.FindName("TxtDomainStatus")
$TxtPrivateStatus     = $Window.FindName("TxtPrivateStatus")
$TxtPublicStatus      = $Window.FindName("TxtPublicStatus")

$TxtTotalInboundCount = $Window.FindName("TxtTotalInboundCount")
$TxtTotalOutboundCount= $Window.FindName("TxtTotalOutboundCount")
$TxtTotalEnabledCount = $Window.FindName("TxtTotalEnabledCount")
$TxtFilteredCount     = $Window.FindName("TxtFilteredCount")

# Profile View Controls
$ChkDomainEnabled     = $Window.FindName("ChkDomainEnabled")
$CmbDomainInbound     = $Window.FindName("CmbDomainInbound")
$CmbDomainOutbound    = $Window.FindName("CmbDomainOutbound")
$BtnSaveDomainProfile = $Window.FindName("BtnSaveDomainProfile")

$ChkPrivateEnabled    = $Window.FindName("ChkPrivateEnabled")
$CmbPrivateInbound    = $Window.FindName("CmbPrivateInbound")
$CmbPrivateOutbound   = $Window.FindName("CmbPrivateOutbound")
$BtnSavePrivateProfile= $Window.FindName("BtnSavePrivateProfile")

$ChkPublicEnabled     = $Window.FindName("ChkPublicEnabled")
$CmbPublicInbound     = $Window.FindName("CmbPublicInbound")
$CmbPublicOutbound    = $Window.FindName("CmbPublicOutbound")
$BtnSavePublicProfile = $Window.FindName("BtnSavePublicProfile")

$Script:AllRulesCache = @()
$Script:CurrentDirection = "Inbound"

# --- 6. CORE REUSABLE HELPERS ---
function Get-CmbText ($Cmb) {
    if (-not $Cmb -or -not $Cmb.SelectedItem) { return "" }
    if ($Cmb.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { return $Cmb.SelectedItem.Content.ToString() }
    return $Cmb.SelectedItem.ToString()
}

function Set-ComboBoxValue ($Cmb, $ValueText) {
    if (-not $ValueText) { return }
    $Val = $ValueText.ToString().Trim()
    for ($i = 0; $i -lt $Cmb.Items.Count; $i++) {
        $ItemObj = $Cmb.Items[$i]
        $ItemText = if ($ItemObj -is [System.Windows.Controls.ComboBoxItem]) { $ItemObj.Content.ToString() } else { $ItemObj.ToString() }
        if ($ItemText -like "*$Val*") { $Cmb.SelectedIndex = $i; return }
    }
}

function Invoke-Events {
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
}

function Update-Status ($Message) {
    $TxtStatusFooter.Text = "$((Get-Date).ToString('HH:mm:ss')) - $Message"
    Invoke-Events
}

function Show-Loading ($Msg) {
    $TxtLoadingMessage.Text = $Msg
    $OverlayLoading.Visibility = [System.Windows.Visibility]::Visible
    Invoke-Events
}

function Hide-Loading {
    $OverlayLoading.Visibility = [System.Windows.Visibility]::Collapsed
    Invoke-Events
}

# --- 7. DATA PIPELINE ENGINE ---
function Sync-FirewallProfiles {
    try {
        $Profiles = Get-NetFirewallProfile -ErrorAction Stop
        
        $UpdateProfileCard = {
            param($ProfObj, $TxtStatus, $ChkEnabled, $CmbInbound, $CmbOutbound)
            if ($ProfObj) {
                $State = if ($ProfObj.Enabled) { "Active" } else { "OFF" }
                $TxtStatus.Text = "$State ($($ProfObj.DefaultInboundAction))"
                $TxtStatus.Foreground = if ($ProfObj.Enabled) { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#34D399") } else { [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F87171") }
                $ChkEnabled.IsChecked = [bool]$ProfObj.Enabled
                Set-ComboBoxValue $CmbInbound $ProfObj.DefaultInboundAction
                Set-ComboBoxValue $CmbOutbound $ProfObj.DefaultOutboundAction
            }
        }

        & $UpdateProfileCard ($Profiles | Where-Object Name -eq 'Domain') $TxtDomainStatus $ChkDomainEnabled $CmbDomainInbound $CmbDomainOutbound
        & $UpdateProfileCard ($Profiles | Where-Object Name -eq 'Private') $TxtPrivateStatus $ChkPrivateEnabled $CmbPrivateInbound $CmbPrivateOutbound
        & $UpdateProfileCard ($Profiles | Where-Object Name -eq 'Public') $TxtPublicStatus $ChkPublicEnabled $CmbPublicInbound $CmbPublicOutbound
    } catch {
        Update-Status "Error loading firewall profiles: $_"
    }
}

function Save-FirewallProfileSettings ($ProfileName, $ChkEnabled, $CmbInbound, $CmbOutbound) {
    try {
        $En = $ChkEnabled.IsChecked
        $InAct = Get-CmbText $CmbInbound
        $OutAct = Get-CmbText $CmbOutbound
        Set-NetFirewallProfile -Profile $ProfileName -Enabled $En -DefaultInboundAction $InAct -DefaultOutboundAction $OutAct -ErrorAction Stop
        Sync-FirewallProfiles
        Update-Status "Saved $ProfileName Profile settings."
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error saving $ProfileName profile: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Sync-FirewallRules {
    Show-Loading "Fetching $($Script:CurrentDirection) firewall rules..."
    Update-Status "Loading $($Script:CurrentDirection) rules..."

    try {
        $RawRules = Get-NetFirewallRule -Direction $Script:CurrentDirection -ErrorAction Stop

        Show-Loading "Processing port & application filters..."
        $PortFilters = @{}
        Get-NetFirewallPortFilter -ErrorAction SilentlyContinue | ForEach-Object { $PortFilters[$_.InstanceID] = $_ }
        
        $AppFilters = @{}
        Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue | ForEach-Object { $AppFilters[$_.InstanceID] = $_ }

        $RuleList = [System.Collections.Generic.List[PSObject]]::new()

        foreach ($r in $RawRules) {
            $InstID = $r.Name
            $PF = $PortFilters[$InstID]
            $AF = $AppFilters[$InstID]

            $ProtocolStr  = if ($PF -and $PF.Protocol) { $PF.Protocol.ToString() } else { "Any" }
            $LocalPortStr = if ($PF -and $PF.LocalPort) { ($PF.LocalPort -join ", ") } else { "Any" }
            $RemotePortStr= if ($PF -and $PF.RemotePort) { ($PF.RemotePort -join ", ") } else { "Any" }
            $ProgramStr   = if ($AF -and $AF.Program) { $AF.Program.ToString() } else { "Any" }

            $IsEnabled = ($r.Enabled -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Enabled]::True -or $r.Enabled -eq "True" -or $r.Enabled -eq 1 -or $r.Enabled -eq $true)
            $IsAllow   = ($r.Action -eq [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.Action]::Allow -or $r.Action -eq "Allow")

            $RuleList.Add([PSCustomObject]@{
                Name          = $r.Name
                DisplayName   = if ($r.DisplayName) { $r.DisplayName } else { $r.Name }
                DisplayGroup  = if ($r.DisplayGroup) { $r.DisplayGroup } else { "-" }
                Direction     = $r.Direction.ToString()
                ActionText    = if ($IsAllow) { "ALLOW" } else { "BLOCK" }
                ActionBg      = if ($IsAllow) { "#064E3B" } else { "#7F1D1D" }
                ActionFg      = if ($IsAllow) { "#34D399" } else { "#F87171" }
                EnabledText   = if ($IsEnabled) { "ENABLED" } else { "DISABLED" }
                EnabledBg     = if ($IsEnabled) { "#1E293B" } else { "#27272A" }
                EnabledFg     = if ($IsEnabled) { "#38BDF8" } else { "#71717A" }
                IsEnabled     = $IsEnabled
                IsAllow       = $IsAllow
                Profile       = $r.Profile.ToString()
                Protocol      = $ProtocolStr
                LocalPort     = $LocalPortStr
                RemotePort    = $RemotePortStr
                Program       = $ProgramStr
                OriginalRule  = $r
            })
        }

        $Script:AllRulesCache = $RuleList

        # Update Counters
        $TxtTotalInboundCount.Text  = (Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue).Count
        $TxtTotalOutboundCount.Text = (Get-NetFirewallRule -Direction Outbound -ErrorAction SilentlyContinue).Count
        $TxtTotalEnabledCount.Text  = (Get-NetFirewallRule -Enabled True -ErrorAction SilentlyContinue).Count

        Invoke-RuleFilter
        Update-Status "Loaded $($Script:AllRulesCache.Count) $($Script:CurrentDirection) rules."
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to query firewall rules: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Update-Status "Failed to load rules."
    } finally {
        Hide-Loading
    }
}

function Invoke-RuleFilter {
    if (-not $Script:AllRulesCache) { return }

    $Query = $TxtSearchQuery.Text.Trim().ToLower()
    $SelAction = Get-CmbText $CmbFilterAction
    $SelStatus = Get-CmbText $CmbFilterStatus
    $SelProfile = Get-CmbText $CmbFilterProfile
    $SelProtocol = Get-CmbText $CmbFilterProtocol

    $FilteredList = [System.Collections.Generic.List[PSObject]]::new()

    foreach ($Rule in $Script:AllRulesCache) {
        if ($Query) {
            $MatchName = $Rule.DisplayName -and $Rule.DisplayName.ToLower().Contains($Query)
            $MatchGroup = $Rule.DisplayGroup -and $Rule.DisplayGroup.ToLower().Contains($Query)
            $MatchProg = $Rule.Program -and $Rule.Program.ToLower().Contains($Query)
            $MatchPort = ($Rule.LocalPort -and $Rule.LocalPort.ToLower().Contains($Query)) -or ($Rule.RemotePort -and $Rule.RemotePort.ToLower().Contains($Query))
            if (-not ($MatchName -or $MatchGroup -or $MatchProg -or $MatchPort)) { continue }
        }

        if ($SelAction -like "*Allow*" -and -not $Rule.IsAllow) { continue }
        if ($SelAction -like "*Block*" -and $Rule.IsAllow) { continue }
        if ($SelStatus -like "*Enabled*" -and -not $Rule.IsEnabled) { continue }
        if ($SelStatus -like "*Disabled*" -and $Rule.IsEnabled) { continue }
        if ($SelProfile -ne "All Profiles" -and $SelProfile -ne "" -and $Rule.Profile -notlike "*$SelProfile*") { continue }
        if ($SelProtocol -ne "All Protocols" -and $SelProtocol -ne "" -and $Rule.Protocol -notlike "*$SelProtocol*") { continue }

        $FilteredList.Add($Rule)
    }

    $GridRules.ItemsSource = $FilteredList
    $TxtFilteredCount.Text = "Showing $($FilteredList.Count) of $($Script:AllRulesCache.Count) rules"
}

# --- 8. MODAL RULE EDITOR ---
function Show-RuleEditorModal ($ExistingRule = $null) {
    [xml]$ModalXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Firewall Rule Editor" Height="580" Width="680"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="#121214" Foreground="#F4F4F5" FontFamily="Segoe UI, Arial">
    <Window.Resources>
        $SharedStylesXaml
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock x:Name="TxtModalTitle" Text="Create New Firewall Rule" FontSize="16" FontWeight="Bold" Foreground="#F4F4F5" Margin="0,0,0,16"/>

        <TabControl Grid.Row="1" Background="#18181C" BorderBrush="#27272A">
            <TabItem Header="General">
                <StackPanel Margin="14">
                    <TextBlock Text="Rule Name *" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                    <TextBox x:Name="TxtRuleName" Margin="0,0,0,12"/>

                    <TextBlock Text="Description" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                    <TextBox x:Name="TxtRuleDescription" Height="50" TextWrapping="Wrap" AcceptsReturn="True" Margin="0,0,0,12"/>

                    <Grid Margin="0,4,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,10,0">
                            <TextBlock Text="Direction" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                            <ComboBox x:Name="CmbRuleDirection">
                                <ComboBoxItem Content="Inbound"/>
                                <ComboBoxItem Content="Outbound"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Column="1">
                            <TextBlock Text="Action" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                            <ComboBox x:Name="CmbRuleAction">
                                <ComboBoxItem Content="Allow"/>
                                <ComboBoxItem Content="Block"/>
                            </ComboBox>
                        </StackPanel>
                    </Grid>

                    <CheckBox x:Name="ChkRuleEnabled" Content="Enable Rule Immediately" IsChecked="True" Foreground="#F4F4F5" Margin="0,8,0,0"/>
                </StackPanel>
            </TabItem>

            <TabItem Header="Program &amp; Ports">
                <StackPanel Margin="14">
                    <TextBlock Text="Program Path (Leave empty for All Programs)" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                    <Grid Margin="0,0,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="90"/>
                        </Grid.ColumnDefinitions>
                        <TextBox x:Name="TxtRuleProgram" Grid.Column="0"/>
                        <Button x:Name="BtnBrowseProgram" Content="Browse..." Grid.Column="1" Margin="6,0,0,0"/>
                    </Grid>

                    <Grid Margin="0,4,0,12">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Column="0" Margin="0,0,10,0">
                            <TextBlock Text="Protocol" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                            <ComboBox x:Name="CmbRuleProtocol">
                                <ComboBoxItem Content="Any"/>
                                <ComboBoxItem Content="TCP"/>
                                <ComboBoxItem Content="UDP"/>
                                <ComboBoxItem Content="ICMPv4"/>
                                <ComboBoxItem Content="ICMPv6"/>
                            </ComboBox>
                        </StackPanel>

                        <StackPanel Grid.Column="1">
                            <TextBlock Text="Local Port (e.g. 80, 443, 8000-8080)" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                            <TextBox x:Name="TxtRuleLocalPort" Text="Any"/>
                        </StackPanel>
                    </Grid>

                    <TextBlock Text="Remote Port" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                    <TextBox x:Name="TxtRuleRemotePort" Text="Any" Margin="0,0,0,12"/>
                </StackPanel>
            </TabItem>

            <TabItem Header="Profiles &amp; Scope">
                <StackPanel Margin="14">
                    <TextBlock Text="Apply to Profiles" FontSize="11" FontWeight="Bold" Foreground="#A1A1AA" Margin="0,0,0,6"/>
                    <StackPanel Orientation="Horizontal" Margin="0,0,0,16">
                        <CheckBox x:Name="ChkProfileDomain" Content="Domain" IsChecked="True" Foreground="#F4F4F5" Margin="0,0,16,0"/>
                        <CheckBox x:Name="ChkProfilePrivate" Content="Private" IsChecked="True" Foreground="#F4F4F5" Margin="0,0,16,0"/>
                        <CheckBox x:Name="ChkProfilePublic" Content="Public" IsChecked="True" Foreground="#F4F4F5"/>
                    </StackPanel>

                    <TextBlock Text="Local IP Scope (comma separated or Subnet e.g. 192.168.1.0/24)" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                    <TextBox x:Name="TxtRuleLocalAddress" Text="Any" Margin="0,0,0,12"/>

                    <TextBlock Text="Remote IP Scope" FontSize="11" Foreground="#A1A1AA" Margin="0,0,0,4"/>
                    <TextBox x:Name="TxtRuleRemoteAddress" Text="Any" Margin="0,0,0,12"/>
                </StackPanel>
            </TabItem>
        </TabControl>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
            <Button x:Name="BtnModalCancel" Content="Cancel" Width="90" Margin="0,0,8,0"/>
            <Button x:Name="BtnModalSave" Content="Save Rule" Width="100" Background="#3B82F6" Foreground="#FFFFFF" BorderBrush="#60A5FA"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $MReader = (New-Object System.Xml.XmlNodeReader $ModalXaml)
    $Modal = [Windows.Markup.XamlReader]::Load($MReader)
    $Modal.Owner = $Window

    if ($Script:AppIcon) {
        try { $Modal.Icon = $Script:AppIcon } catch {}
    }

    $TxtModalTitle        = $Modal.FindName("TxtModalTitle")
    $TxtRuleName          = $Modal.FindName("TxtRuleName")
    $TxtRuleDescription   = $Modal.FindName("TxtRuleDescription")
    $CmbRuleDirection     = $Modal.FindName("CmbRuleDirection")
    $CmbRuleAction        = $Modal.FindName("CmbRuleAction")
    $ChkRuleEnabled       = $Modal.FindName("ChkRuleEnabled")
    $TxtRuleProgram       = $Modal.FindName("TxtRuleProgram")
    $BtnBrowseProgram     = $Modal.FindName("BtnBrowseProgram")
    $CmbRuleProtocol      = $Modal.FindName("CmbRuleProtocol")
    $TxtRuleLocalPort     = $Modal.FindName("TxtRuleLocalPort")
    $TxtRuleRemotePort    = $Modal.FindName("TxtRuleRemotePort")
    $ChkProfileDomain     = $Modal.FindName("ChkProfileDomain")
    $ChkProfilePrivate    = $Modal.FindName("ChkProfilePrivate")
    $ChkProfilePublic     = $Modal.FindName("ChkProfilePublic")
    $BtnModalCancel       = $Modal.FindName("BtnModalCancel")
    $BtnModalSave         = $Modal.FindName("BtnModalSave")

    Set-ComboBoxValue $CmbRuleDirection $Script:CurrentDirection

    if ($ExistingRule) {
        $TxtModalTitle.Text = "Edit Rule: $($ExistingRule.DisplayName)"
        $TxtRuleName.Text = $ExistingRule.DisplayName
        $TxtRuleName.IsReadOnly = $true
        Set-ComboBoxValue $CmbRuleDirection $ExistingRule.Direction
        Set-ComboBoxValue $CmbRuleAction $ExistingRule.ActionText
        $ChkRuleEnabled.IsChecked = $ExistingRule.IsEnabled
        $TxtRuleProgram.Text = if ($ExistingRule.Program -ne "Any") { $ExistingRule.Program } else { "" }
        Set-ComboBoxValue $CmbRuleProtocol $ExistingRule.Protocol
        $TxtRuleLocalPort.Text = $ExistingRule.LocalPort
        $TxtRuleRemotePort.Text = $ExistingRule.RemotePort
        $ChkProfileDomain.IsChecked = ($ExistingRule.Profile -like "*Domain*")
        $ChkProfilePrivate.IsChecked = ($ExistingRule.Profile -like "*Private*")
        $ChkProfilePublic.IsChecked = ($ExistingRule.Profile -like "*Public*")
    }

    $BtnBrowseProgram.Add_Click({
        $OFD = New-Object System.Windows.Forms.OpenFileDialog
        $OFD.Filter = "Executable Files (*.exe)|*.exe|All Files (*.*)|*.*"
        $OFD.Title = "Select Application Executable"
        if ($OFD.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $TxtRuleProgram.Text = $OFD.FileName
        }
    })

    $BtnModalCancel.Add_Click({
        $Modal.DialogResult = $false
        $Modal.Close()
    })

    $BtnModalSave.Add_Click({
        $RuleName = $TxtRuleName.Text.Trim()
        if (-not $RuleName) {
            [System.Windows.Forms.MessageBox]::Show("Please enter a rule name.", "Validation Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }

        $ProfList = @()
        if ($ChkProfileDomain.IsChecked) { $ProfList += "Domain" }
        if ($ChkProfilePrivate.IsChecked) { $ProfList += "Private" }
        if ($ChkProfilePublic.IsChecked) { $ProfList += "Public" }
        if ($ProfList.Count -eq 0) { $ProfList = "Any" }

        $Dir  = Get-CmbText $CmbRuleDirection
        $Act  = Get-CmbText $CmbRuleAction
        $En   = if ($ChkRuleEnabled.IsChecked) { "True" } else { "False" }
        $Prog = $TxtRuleProgram.Text.Trim()
        $Prot = Get-CmbText $CmbRuleProtocol
        $LPort= $TxtRuleLocalPort.Text.Trim()
        $RPort= $TxtRuleRemotePort.Text.Trim()

        try {
            if ($ExistingRule) {
                Set-NetFirewallRule -Name $ExistingRule.Name -Enabled $En -Action $Act -Profile $ProfList -ErrorAction Stop

                if ($Prot -ne "Any" -or $LPort -ne "Any" -or $RPort -ne "Any") {
                    $PortParams = @{ AssociatedRule = $ExistingRule.OriginalRule }
                    if ($Prot -ne "Any") { $PortParams.Protocol = $Prot }
                    if ($LPort -ne "Any") { $PortParams.LocalPort = $LPort }
                    if ($RPort -ne "Any") { $PortParams.RemotePort = $RPort }
                    Set-NetFirewallPortFilter @PortParams -ErrorAction SilentlyContinue
                }

                if ($Prog) {
                    Set-NetFirewallApplicationFilter -AssociatedRule $ExistingRule.OriginalRule -Program $Prog -ErrorAction SilentlyContinue
                }
                Update-Status "Updated firewall rule '$RuleName'."
            } else {
                $Params = @{
                    DisplayName = $RuleName
                    Direction   = $Dir
                    Action      = $Act
                    Enabled     = $En
                    Profile     = $ProfList
                }
                if ($TxtRuleDescription.Text.Trim()) { $Params.Description = $TxtRuleDescription.Text.Trim() }
                if ($Prog) { $Params.Program = $Prog }
                if ($Prot -ne "Any") { $Params.Protocol = $Prot }
                if ($LPort -ne "Any") { $Params.LocalPort = $LPort }
                if ($RPort -ne "Any") { $Params.RemotePort = $RPort }

                New-NetFirewallRule @Params -ErrorAction Stop
                Update-Status "Created new firewall rule '$RuleName'."
            }

            $Modal.DialogResult = $true
            $Modal.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error saving firewall rule: $_", "Operation Failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

    if ($Modal.ShowDialog() -eq $true) {
        Sync-FirewallRules
    }
}

# --- 9. EVENT BINDINGS ---
$Window.Add_Loaded({
    Sync-FirewallProfiles
    Sync-FirewallRules
})

$NavInbound.Add_Checked({
    $Script:CurrentDirection = "Inbound"
    $ViewRules.Visibility = [System.Windows.Visibility]::Visible
    $ViewProfiles.Visibility = [System.Windows.Visibility]::Collapsed
    Sync-FirewallRules
})

$NavOutbound.Add_Checked({
    $Script:CurrentDirection = "Outbound"
    $ViewRules.Visibility = [System.Windows.Visibility]::Visible
    $ViewProfiles.Visibility = [System.Windows.Visibility]::Collapsed
    Sync-FirewallRules
})

$NavProfiles.Add_Checked({
    $ViewRules.Visibility = [System.Windows.Visibility]::Collapsed
    $ViewProfiles.Visibility = [System.Windows.Visibility]::Visible
    Sync-FirewallProfiles
})

$TxtSearchQuery.Add_TextChanged({ Invoke-RuleFilter })
$CmbFilterAction.Add_SelectionChanged({ Invoke-RuleFilter })
$CmbFilterStatus.Add_SelectionChanged({ Invoke-RuleFilter })
$CmbFilterProfile.Add_SelectionChanged({ Invoke-RuleFilter })
$CmbFilterProtocol.Add_SelectionChanged({ Invoke-RuleFilter })

$BtnNewRule.Add_Click({ Show-RuleEditorModal })

$BtnEditRule.Add_Click({
    $Sel = $GridRules.SelectedItem
    if (-not $Sel) {
        [System.Windows.Forms.MessageBox]::Show("Please select a firewall rule to edit.", "Selection Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    Show-RuleEditorModal -ExistingRule $Sel
})

$BtnToggleRule.Add_Click({
    $Sel = $GridRules.SelectedItem
    if (-not $Sel) {
        [System.Windows.Forms.MessageBox]::Show("Please select a rule to toggle.", "Selection Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    try {
        if ($Sel.IsEnabled) {
            Disable-NetFirewallRule -Name $Sel.Name -ErrorAction Stop
            Update-Status "Disabled rule '$($Sel.DisplayName)'"
        } else {
            Enable-NetFirewallRule -Name $Sel.Name -ErrorAction Stop
            Update-Status "Enabled rule '$($Sel.DisplayName)'"
        }
        Sync-FirewallRules
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error toggling rule: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})

$BtnDeleteRule.Add_Click({
    $Sel = $GridRules.SelectedItem
    if (-not $Sel) {
        [System.Windows.Forms.MessageBox]::Show("Please select a rule to delete.", "Selection Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }

    $Confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to permanently delete rule '$($Sel.DisplayName)'?", "Confirm Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($Confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Remove-NetFirewallRule -Name $Sel.Name -ErrorAction Stop
            Update-Status "Deleted rule '$($Sel.DisplayName)'."
            Sync-FirewallRules
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Error deleting rule: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$BtnRefreshAll.Add_Click({
    Sync-FirewallProfiles
    Sync-FirewallRules
})

$BtnManageProfiles.Add_Click({
    $NavProfiles.IsChecked = $true
})

# Backup Export
$BtnExportBackup.Add_Click({
    $SFD = New-Object System.Windows.Forms.SaveFileDialog
    $SFD.Filter = "Windows Firewall Policy File (*.wfw)|*.wfw"
    $SFD.Title = "Export Firewall Policy Backup"
    $SFD.FileName = "FirewallPolicy_$(Get-Date -Format 'yyyyMMdd_HHmmss').wfw"

    if ($SFD.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Show-Loading "Exporting firewall policy..."
            cmd.exe /c "netsh advfirewall export `"$($SFD.FileName)`""
            Hide-Loading
            [System.Windows.Forms.MessageBox]::Show("Firewall policy exported successfully to:`n$($SFD.FileName)", "Backup Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Update-Status "Exported policy backup to $($SFD.FileName)"
        } catch {
            Hide-Loading
            [System.Windows.Forms.MessageBox]::Show("Export failed: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

# Backup Import
$BtnImportBackup.Add_Click({
    $OFD = New-Object System.Windows.Forms.OpenFileDialog
    $OFD.Filter = "Windows Firewall Policy File (*.wfw)|*.wfw"
    $OFD.Title = "Import Firewall Policy Backup"

    if ($OFD.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $Confirm = [System.Windows.Forms.MessageBox]::Show("Importing a firewall policy will OVERWRITE all current firewall settings. Continue?", "Confirm Overwrite", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($Confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            try {
                Show-Loading "Importing firewall policy..."
                cmd.exe /c "netsh advfirewall import `"$($OFD.FileName)`""
                Hide-Loading
                [System.Windows.Forms.MessageBox]::Show("Firewall policy imported successfully!", "Import Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                Sync-FirewallProfiles
                Sync-FirewallRules
            } catch {
                Hide-Loading
                [System.Windows.Forms.MessageBox]::Show("Import failed: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }
    }
})

# Quick Profile Actions
$BtnQuickDisableAll.Add_Click({
    $Confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to DISABLE Windows Firewall across all profiles (Domain, Private, Public)? This leaves your system exposed.", "Security Warning", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($Confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False -ErrorAction Stop
            Sync-FirewallProfiles
            Update-Status "WARNING: Disabled firewall across all profiles."
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Failed to update profile settings: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$BtnQuickRestoreDefaults.Add_Click({
    $Confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to restore Windows Firewall to default settings? All custom rules will be deleted.", "Restore Defaults", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($Confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            Show-Loading "Restoring Windows Firewall default policies..."
            cmd.exe /c "netsh advfirewall reset"
            Hide-Loading
            [System.Windows.Forms.MessageBox]::Show("Windows Firewall reset to default policies.", "Reset Complete", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            Sync-FirewallProfiles
            Sync-FirewallRules
        } catch {
            Hide-Loading
            [System.Windows.Forms.MessageBox]::Show("Failed to reset firewall: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$BtnSaveDomainProfile.Add_Click({ Save-FirewallProfileSettings "Domain" $ChkDomainEnabled $CmbDomainInbound $CmbDomainOutbound })
$BtnSavePrivateProfile.Add_Click({ Save-FirewallProfileSettings "Private" $ChkPrivateEnabled $CmbPrivateInbound $CmbPrivateOutbound })
$BtnSavePublicProfile.Add_Click({ Save-FirewallProfileSettings "Public" $ChkPublicEnabled $CmbPublicInbound $CmbPublicOutbound })

# --- 10. RUN APPLICATION ---
$Window.ShowDialog() | Out-Null
