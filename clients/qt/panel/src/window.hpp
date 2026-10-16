// The panel's window: everything shown is composed from the picture — the channel's own state, and for
// each unit what the channel may address on it. Nothing here names a unit, a Plugin or a domain; a
// payload is shown as text and sent as text.
#ifndef PANEL_WINDOW_HPP
#define PANEL_WINDOW_HPP

#include <functional>
#include <map>
#include <memory>
#include <string>

#include <QLabel>
#include <QPointer>
#include <QVBoxLayout>
#include <QWidget>

#include "picture.hpp"

namespace panel {

// What the window asks of the channel. Each act answers with a line to show, and throws a refusal or a
// failure, which is shown instead; acts run away from the window's thread.
struct Acts {
    virtual ~Acts() = default;
    virtual std::string command(const std::string &unit, const std::string &type, const std::string &payload) = 0;
    virtual std::string ask(const std::string &unit, const std::string &type, const std::string &payload) = 0;
    virtual std::string start(const std::string &unit, const std::string &stream) = 0;
    virtual std::string stop(const std::string &unit, const std::string &stream) = 0;
    // Watches a stream until watched is called again for it; says each frame through told.
    virtual std::string watch(const std::string &unit, const std::string &stream,
                              std::function<void(const std::string &)> told) = 0;
    virtual std::string reclaim() = 0;
};

class Window : public QWidget {
  public:
    explicit Window(Acts &acts, QWidget *parent = nullptr);

    // Draws the picture: a unit's card is rebuilt only when what the channel may address on it changed,
    // and its state is refreshed in place.
    void draw(const Picture &picture);

  private:
    struct Card {
        QWidget *widget;
        QLabel *state;
        std::string shape;
    };

    QWidget *card(const v1::UnitRecord &unit);
    void row(QVBoxLayout *into, const QString &label, const QString &name,
             std::function<std::string(const std::string &)> act, bool payload);
    void run(QPointer<QLabel> output, std::function<std::string()> act);

    Acts &acts_;
    QLabel *channel_;
    QWidget *reclaim_;
    QVBoxLayout *units_;
    std::map<std::string, Card> cards_;
};

// A refusal or a failure, as the window says it.
std::string said(const std::exception &e);

} // namespace panel

#endif
