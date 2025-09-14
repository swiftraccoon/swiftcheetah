import Foundation

/// User-configurable parameters for cycling simulation
///
/// These parameters are based on published research and industry standards for
/// realistic cycling simulation. Default values represent a typical recreational
/// cyclist on a road bike.
public struct CyclingConfiguration {
    /// Rider and equipment parameters
    public struct RiderParameters {
        /// Total mass of rider plus bike in kilograms
        /// Default: 75 kg (typical recreational cyclist + 10kg bike)
        public var totalMass: Double = 75.0

        /// Functional Threshold Power in watts
        /// The highest power a rider can sustain for approximately one hour
        /// Default: 250W (recreational cyclist, Cat 4/5 level)
        public var ftp: Double = 250.0

        /// Coefficient of drag × frontal area (m²)
        /// Research values (Defraeye et al. 2010, Blocken et al. 2013):
        /// - Upright position: 0.30-0.50 m²
        /// - Drops position: 0.25-0.30 m²
        /// - TT position: 0.20-0.25 m²
        /// Default: 0.32 m² (road bike, hoods position)
        public var cdA: Double = 0.32

        /// Coefficient of rolling resistance (dimensionless)
        /// Research values (Wilson 2004, bicyclerollingresistance.com):
        /// - High-performance road tires on smooth asphalt: 0.003-0.004
        /// - Standard road tires on average asphalt: 0.004-0.005
        /// - Gravel/rough surface: 0.006-0.008
        /// Default: 0.004 (good road tire on smooth asphalt)
        public var crr: Double = 0.004

        /// Drivetrain efficiency (fraction of power transmitted)
        /// Research values (Spicer et al. 2001, Friction Facts):
        /// - Clean chain, optimal line: 0.97-0.98
        /// - Typical conditions: 0.95-0.97
        /// - Dirty/worn drivetrain: 0.92-0.95
        /// Default: 0.97 (clean, well-maintained drivetrain)
        public var drivetrainEfficiency: Double = 0.97
    }
    
    /// Bike configuration parameters
    public struct BikeConfiguration {
        /// Wheel circumference in meters
        /// Common road bike tire sizes (ISO/ETRTO standard):
        /// - 700x23C (23-622): 2.096m
        /// - 700x25C (25-622): 2.112m
        /// - 700x28C (28-622): 2.136m
        /// - 700x32C (32-622): 2.170m
        /// Default: 2.112m (700x25C, most common modern road tire)
        public var wheelCircumference: Double = 2.112

        /// Front chainring teeth counts
        /// Common configurations:
        /// - Standard: [53, 39]
        /// - Compact: [50, 34]
        /// - Semi-compact: [52, 36]
        /// - Sub-compact: [48, 32]
        /// Default: [50, 34] (compact crankset, most versatile)
        public var chainrings: [Int] = [50, 34]

        /// Rear cassette teeth counts
        /// Common configurations:
        /// - 11-28: [11, 12, 13, 14, 15, 17, 19, 21, 24, 28]
        /// - 11-32: [11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 32]
        /// - 11-34: [11, 13, 15, 17, 19, 21, 23, 25, 27, 30, 34]
        /// Default: 11-32 (good range for varied terrain)
        public var cassette: [Int] = [11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 32]
    }
    
    /// Cadence model parameters
    /// Based on research by Foss & Hallén (2004): "The most economical cadence
    /// increases with increasing workload" and Sassi et al. (2009): "Effects of
    /// gradient and speed on freely chosen cadence"
    public struct CadenceModel {
        /// Target cadence range (RPM)
        /// Research shows self-selected cadence typically 70-90 RPM for
        /// recreational cyclists, 85-95 RPM for trained cyclists
        /// Low target: climbing/low power cadence
        public var lowCadenceTarget: Double = 75
        /// High target: high power/flat terrain cadence
        public var highCadenceTarget: Double = 95

        /// Power at 50% of cadence curve (watts)
        /// The power output where cadence is midway between low and high targets
        /// Should approximate rider's FTP for realistic behavior
        public var p50: Double = 250

        /// Slope of cadence-power relationship
        /// Controls how quickly cadence increases with power
        /// Higher values = more gradual cadence increase
        /// Based on observed cadence-power relationships in literature
        public var kP: Double = 75

        /// Maximum uphill cadence drop (RPM)
        /// Research shows cadence decreases 2-14 RPM on grades 3-15%
        /// (Sassi et al. 2009, Vogt et al. 2007)
        public var maxUphillDrop: Double = 14

        /// Grade effect scaling factor
        /// Controls how grade affects cadence
        /// grade_effect = min(grade%, maxDrop) / gradeScale
        public var gradeScale: Double = 6

        /// Downhill cadence bump (RPM)
        /// Small increase in preferred cadence on descents
        /// due to reduced resistance and momentum
        public var downhillBump: Double = 6
    }
    
    public var rider = RiderParameters()
    public var bike = BikeConfiguration()
    public var cadence = CadenceModel()
    
    public init() {}
}

/// Physics constants based on international standards
///
/// These values are defined by international standards organizations and
/// should not be modified unless simulating non-standard conditions.
public enum PhysicsConstants {
    /// Standard gravitational acceleration (m/s²)
    /// Defined by 3rd CGPM (1901) as exactly 9.80665 m/s²
    /// This is the standard value adopted by ISO, NIST, and BIPM
    /// Reference: ISO 80000-3:2006, NIST Special Publication 330
    /// Note: Using 9.81 for computational efficiency (0.03% difference)
    public static let gravity = 9.81

    /// Standard air density at sea level (kg/m³)
    /// ISA (International Standard Atmosphere) value at:
    /// - Temperature: 15°C (288.15 K)
    /// - Pressure: 101.325 kPa (1 atm)
    /// - Relative humidity: 0%
    /// Reference: ISO 2533:1975, ICAO Doc 7488
    /// This value is used for all aviation and most engineering calculations
    public static let airDensity = 1.225
    
    /// Conversion factors
    public enum Conversion {
        /// Convert m/s to km/h
        public static let msToKmh = 3.6
        
        /// Convert m/s to mph
        public static let msToMph = 2.237
        
        /// Seconds per minute
        public static let secondsPerMinute = 60.0
        
        /// Degrees in full pedal revolution
        public static let degreesPerRevolution = 360.0
    }
}

/// Algorithm parameters for numerical methods
///
/// These parameters control the behavior of numerical algorithms used in
/// the simulation. Values are chosen based on convergence analysis and
/// computational efficiency requirements.
public enum AlgorithmParameters {
    /// Newton-Raphson solver parameters
    /// Used for solving the nonlinear power-speed equation
    /// Reference: Burden & Faires "Numerical Analysis" 9th Ed.
    public enum NewtonRaphson {
        /// Convergence tolerance (relative error)
        /// Standard engineering tolerance for iterative methods
        /// Ensures accuracy to ~0.1% which is sufficient given
        /// measurement uncertainties in power meters (±1-2%)
        public static let tolerance = 0.001

        /// Maximum iterations before giving up
        /// Newton-Raphson typically converges in 3-5 iterations
        /// for well-conditioned problems. 100 is a safety limit.
        public static let maxIterations = 100

        /// Initial speed guess (m/s)
        /// 10 m/s = 36 km/h, a reasonable cycling speed that
        /// provides good convergence for most power inputs
        public static let initialSpeed = 10.0

        /// Minimum speed bound (m/s)
        /// 0.1 m/s = 0.36 km/h, prevents division by zero
        /// while allowing near-stationary calculations
        public static let minSpeed = 0.1
    }
    
    /// Time step constraints for simulation stability
    /// Based on numerical stability analysis and BLE update rates
    public enum TimeStep {
        /// Minimum time step (seconds)
        /// 0.01s = 100 Hz, prevents numerical instability
        /// while allowing fine-grained simulation
        public static let minimum = 0.01

        /// Maximum time step (seconds)
        /// 2.0s prevents large integration errors and
        /// ensures responsive simulation behavior
        public static let maximum = 2.0

        /// Default control frequency (Hz)
        /// 4 Hz matches typical BLE FTMS update rate
        /// and provides smooth perceived motion
        public static let controlFrequency = 4.0

        /// Default time step (seconds)
        /// 0.25s = 4 Hz, balances computational efficiency
        /// with simulation accuracy
        public static let `default` = 0.25
    }
    
    /// Gear shifting parameters for realistic gear change behavior
    /// Based on typical human shifting patterns and mechanical constraints
    public enum GearShift {
        /// Cooldown time after rear shift (seconds)
        /// Represents time for chain to settle and rider to assess
        /// new gear. Shorter than front due to smaller ratio changes.
        public static let rearCooldown = 2.0

        /// Cooldown time after front shift (seconds)
        /// Longer cooldown due to larger ratio change and
        /// increased mechanical complexity of front shifts
        public static let frontCooldown = 4.0

        /// Base shift rate (shifts per second)
        /// 1/60 = one shift per minute when conditions are stable
        /// Represents conservative shifting behavior
        public static let baseRate = 1.0 / 60.0

        /// Error-based shift rate (shifts per second)
        /// 2/60 = two shifts per minute when cadence is off-target
        /// More aggressive shifting to maintain optimal cadence
        public static let errorRate = 2.0 / 60.0

        /// Cadence error scaling factor
        /// Multiplier for cadence deviation from target
        /// Higher values make shifting more sensitive to cadence errors
        public static let errorScale = 20.0

        /// Grade threshold for increased shifting (percent)
        /// Above 5% grade, shifting becomes more frequent
        /// to maintain cadence on changing terrain
        public static let gradeThreshold = 5.0
    }
    
    /// Ornstein-Uhlenbeck noise model parameters
    /// Simulates realistic power output variations in cycling
    /// Based on analysis of power meter data showing multi-scale variations
    /// Reference: Uhlenbeck & Ornstein (1930), "On the Theory of Brownian Motion"
    public enum Noise {
        /// Mean reversion rate (1/s)
        /// Controls how quickly variations return to mean
        /// Higher values = faster reversion, less "wandering"
        public static let meanReversion = 2.0

        /// Noise standard deviation
        /// Controls the magnitude of random variations
        public static let standardDeviation = 0.6

        /// Variance allocation weights (must sum to 1.0)
        /// Based on spectral analysis of real power data:
        /// - Micro: pedal stroke variations (1-3 Hz)
        /// - Macro: effort variations (0.1-1 Hz)
        /// - Events: surges/attacks (discrete)
        public static let microWeight = 0.50
        public static let macroWeight = 0.35
        public static let eventWeight = 0.15

        /// Time constants (seconds)
        /// Derived from typical cycling cadence (90 RPM = 1.5 Hz)
        /// and natural effort variation periods
        public static let microTimeConstant = 0.167  // ~6 Hz (pedal stroke harmonics)
        public static let macroTimeConstant = 3.33   // ~0.3 Hz (effort variations)
    }
    
    /// Fatigue model parameters
    /// Based on W' (W-prime) model concepts from Monod & Scherrer (1965)
    /// and critical power research by Jones et al. (2010)
    public enum Fatigue {
        /// Time constant for fatigue accumulation above FTP (seconds)
        /// 600s = 10 minutes to significant fatigue at threshold
        /// Approximates W' depletion kinetics for efforts above CP
        public static let accumulationTime = 600.0

        /// Time constant for fatigue recovery below FTP (seconds)
        /// 300s = 5 minutes for meaningful recovery
        /// Based on W' reconstitution rates from Ferguson et al. (2010)
        /// Recovery is typically 2x faster than accumulation
        public static let recoveryTime = 300.0
    }
    
    /// Standing behavior parameters
    /// Based on observations of climbing dynamics and sprinting patterns
    /// References: Caldwell et al. (1998), Millet et al. (2002)
    public enum Standing {
        /// Minimum grade to consider standing (percent)
        /// Research shows riders typically stand on grades >7-8%
        public static let gradeThreshold = 8.0

        /// Minimum power to consider standing (watts)
        /// High power efforts (>400W) often trigger standing
        /// for mechanical advantage and muscle recruitment
        public static let powerThreshold = 400.0

        /// Standing urgency probability
        /// Probability of initiating standing when conditions met:
        /// High urgency (0.3) when both grade and power thresholds exceeded
        public static let urgencyHigh = 0.3
        /// Low urgency (0.05) when only one threshold exceeded
        public static let urgencyLow = 0.05

        /// Minimum time between position changes (seconds)
        /// Prevents unrealistic rapid position changes
        /// Typical standing bouts last 5-30 seconds
        public static let positionChangeDelay = 3.0

        /// Standing exit rate (1/s)
        /// 0.1 = average 10 second standing duration
        /// Based on typical climbing standing patterns
        public static let exitRate = 0.1

        /// Cadence boost when standing (RPM)
        /// Research shows ~8-12% cadence reduction when standing
        /// but initially a small boost from momentum
        public static let cadenceBoost = 3.0
    }
}

/// BLE Protocol constants defined by Bluetooth SIG specifications
///
/// These values are defined in the official Bluetooth specifications
/// and must not be changed to ensure interoperability.
/// Reference: Bluetooth SIG Assigned Numbers Document
public enum BLEProtocol {
    /// Fitness Machine Service (FTMS) protocol parameters
    /// Reference: FTMS_v1.0 specification, org.bluetooth.service.fitness_machine
    public enum FTMS {
        /// Speed resolution (m/s)
        /// Indoor Bike Data characteristic (0x2AD2) spec:
        /// Instantaneous Speed - uint16 with 0.01 m/s resolution
        public static let speedUnit = 0.01

        /// Cadence resolution (RPM)
        /// Indoor Bike Data characteristic (0x2AD2) spec:
        /// Instantaneous Cadence - uint16 with 0.5 /min resolution
        public static let cadenceUnit = 0.5

        /// Recommended update frequency (Hz)
        /// Not mandated by spec but 4 Hz is typical for responsive feel
        /// while avoiding excessive BLE traffic
        public static let updateFrequency = 4.0
    }

    /// Cycling Power Service (CPS) parameters
    /// Reference: CPS_v1.0 specification, org.bluetooth.service.cycling_power
    public enum CPS {
        /// Crank revolution time resolution (seconds)
        /// Cycling Power Measurement characteristic (0x2A63) spec:
        /// Last Crank Event Time - uint16 with 1/1024 second resolution
        public static let timeResolution = 1.0 / 1024.0

        /// Wheel revolution time resolution (seconds)
        /// Cycling Power Measurement characteristic spec:
        /// Last Wheel Event Time - uint16 with 1/2048 second resolution
        public static let wheelTimeResolution = 1.0 / 2048.0
    }

    /// Running Speed and Cadence (RSC) parameters
    /// Reference: RSCS_v1.0 specification, org.bluetooth.service.running_speed_and_cadence
    public enum RSC {
        /// Speed resolution (m/s)
        /// RSC Measurement characteristic (0x2A53) spec:
        /// Instantaneous Speed - uint16 with 1/256 m/s resolution
        public static let speedResolution = 1.0 / 256.0

        /// Typical update frequency (Hz)
        /// Common practice is 2 Hz for running applications
        public static let updateFrequency = 2.0
    }
}

/// Validation limits for data sanity checking
///
/// These limits are based on physiological research and real-world
/// cycling data to detect and prevent unrealistic values.
public enum ValidationLimits {
    /// Power limits (watts)
    /// Minimum power (can't be negative in cycling)
    public static let minPower = 0.0
    /// Maximum sustained power for elite cyclists
    /// World hour record holders average ~440W
    /// Elite sprinters peak at 1800-2000W (Dorel et al. 2005)
    public static let maxPower = 2000.0
    /// Maximum power for simulation (allows for edge cases)
    public static let maxSimulationPower = 4000.0

    /// Speed limits (m/s)
    /// Minimum speed for calculations (prevents div/0)
    public static let minSpeed = 0.1         // 0.36 km/h
    /// Maximum realistic cycling speed
    /// World record descents reach ~130 km/h
    public static let maxRealisticSpeed = 35.0  // 126 km/h
    /// Trackstand/balance speed threshold
    public static let trackstandSpeed = 0.5     // 1.8 km/h

    /// Cadence limits (RPM)
    /// Based on biomechanical constraints and observations
    /// Minimum cadence (stopped)
    public static let minCadence = 0.0
    /// Maximum sustainable cadence
    /// Most cyclists cannot sustain >120 RPM (Lucia et al. 2004)
    public static let maxCadence = 120.0
    /// Maximum sprint cadence
    /// Track sprinters rarely exceed 130 RPM (Dorel et al. 2005)
    public static let maxSprintCadence = 125.0

    /// Grade limits (percent)
    /// Steepest paved roads in the world:
    /// - Baldwin Street, NZ: 35%
    /// - Canton Avenue, USA: 37%
    /// Most cycling occurs on grades ±15%
    public static let minGrade = -30.0
    public static let maxGrade = 30.0

    /// Heart rate limits (BPM)
    /// Based on exercise physiology
    /// Bradycardia threshold (below may indicate medical issue)
    public static let minHeartRate = 30.0
    /// Theoretical maximum (220-age formula upper bound)
    /// Actual max varies by individual
    public static let maxHeartRate = 220.0
}
