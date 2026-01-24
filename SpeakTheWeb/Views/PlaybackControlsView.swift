import SwiftUI

/// View containing playback controls for the text-to-speech
struct PlaybackControlsView: View {
    @ObservedObject var viewModel: ReaderViewModel
    @State private var isDragging = false
    @State private var dragProgress = 0.0

    /// Determines the appropriate icon for the play button
    private var playButtonIcon: String {
        if viewModel.playbackIsPlaying {
            return "pause.circle.fill"
        } else if viewModel.playbackIsFinished {
            return "arrow.counterclockwise.circle.fill"
        } else {
            return "play.circle.fill"
        }
    }

    var body: some View {
        let displayProgress = isDragging ? dragProgress : viewModel.playbackProgress

        VStack(spacing: 12) {
            if viewModel.isGeneratingAudio {
                let phaseText = viewModel.sherpaGenerationPhase ?? "Generating audio…"
                VStack(spacing: 6) {
                    ProgressView(phaseText)
                        .font(.caption)
                }
            }

            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 10)
                            .cornerRadius(5)

                        // Progress track
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * displayProgress, height: 10)
                            .cornerRadius(5)

                        // Grab handle
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 22, height: 22)
                            .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                            .offset(x: max(0, min(geometry.size.width - 22, geometry.size.width * displayProgress - 11)))
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let percentage = value.location.x / geometry.size.width
                                let clampedPercentage = max(0, min(1, percentage))
                                dragProgress = clampedPercentage
                                isDragging = true
                            }
                            .onEnded { value in
                                let percentage = value.location.x / geometry.size.width
                                let clampedPercentage = max(0, min(1, percentage))
                                dragProgress = clampedPercentage
                                isDragging = false
                                if let article = viewModel.article {
                                    let position = Int(Double(article.content.count) * clampedPercentage)
                                    viewModel.seekTo(position: position)
                                }
                            }
                    )
                }
                .frame(height: 22)

                // Progress text
                HStack {
                    Text(viewModel.progressText)
                    Spacer()
                    Text(viewModel.estimatedTimeRemaining)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Main controls
            HStack(spacing: 32) {
                // Skip backward
                Button(action: { viewModel.skipBackward() }) {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                }

                // Play/Pause/Replay
                Button(action: { viewModel.togglePlayPause() }) {
                    ZStack {
                        Image(systemName: playButtonIcon)
                            .font(.system(size: 56))
                        if viewModel.isGeneratingAudio {
                            ProgressView()
                        }
                    }
                }

                // Skip forward
                Button(action: { viewModel.skipForward() }) {
                    Image(systemName: "goforward.15")
                        .font(.title2)
                }
            }
            .foregroundColor(.accentColor)
            .disabled(viewModel.isGeneratingAudio)

            // Speed control
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(.secondary)

                Picker("Speed", selection: $viewModel.selectedRateIndex) {
                    ForEach(0 ..< SpeechService.ratePresets.count, id: \.self) { index in
                        Text(SpeechService.ratePresets[index].name)
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            .disabled(viewModel.isGeneratingAudio)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .allowsHitTesting(!viewModel.isGeneratingAudio)
    }
}

#Preview {
    PlaybackControlsView(viewModel: ReaderViewModel())
}
